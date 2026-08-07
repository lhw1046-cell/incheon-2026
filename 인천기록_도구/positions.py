# -*- coding: utf-8 -*-
"""K리그1 전 경기 결과 → 라운드별 순위 이력 계산.

league_results.json 스키마:
  {"1": [["대전",1,"안양",1], ...], "2": [...], ...}     # [홈, 홈골, 원정, 원정골]
새 라운드는 update.py 의 payload["league_results"] 로 추가하면 병합된다.
"""
import json, os, re

KO = {"Seoul": "서울", "Ulsan HD": "울산", "Jeonbuk Hyundai Motors": "전북",
      "Gangwon": "강원", "Anyang": "안양", "Incheon United": "인천",
      "Jeju United": "제주", "Pohang Steelers": "포항", "Daejeon Citizen": "대전",
      "Gimcheon Sangmu": "김천", "Bucheon 1995": "부천", "Gwangju": "광주"}
TEAMS = ["서울", "울산", "전북", "강원", "안양", "인천", "제주", "포항", "대전", "김천", "부천", "광주"]
RESULTS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "league_results.json")

_NAMES = sorted(KO, key=len, reverse=True)
_PAT = re.compile(r"^(" + "|".join(re.escape(n) for n in _NAMES) +
                  r")\s+(\d+)\s+(" + "|".join(re.escape(n) for n in _NAMES) + r")\s+(\d+)$")


def parse_line(line):
    """soccer365 영문 표기 한 줄 → ['홈', 홈골, '원정', 원정골] (한글 변환)"""
    m = _PAT.match(line.strip())
    if not m:
        raise ValueError(f"파싱 실패: {line}")
    return [KO[m.group(1)], int(m.group(2)), KO[m.group(3)], int(m.group(4))]


def load():
    if os.path.exists(RESULTS_FILE):
        return json.load(open(RESULTS_FILE, encoding="utf-8"))
    return {}


def save(data):
    json.dump(data, open(RESULTS_FILE, "w", encoding="utf-8"), ensure_ascii=False, indent=1)


def compute_positions(rounds=None):
    """{라운드: [[홈,홈골,원정,원정골], ...]} → (history, final_table)
       순위 기준(K리그): 승점 → 다득점 → 골득실 → 다승"""
    rounds = rounds if rounds is not None else load()
    S = {t: dict(pld=0, w=0, d=0, l=0, gf=0, ga=0, pts=0) for t in TEAMS}
    history = {t: [] for t in TEAMS}
    order = TEAMS
    for rd in sorted(rounds, key=int):
        for h, hg, a, ag in rounds[rd]:
            for t, gf, ga in ((h, hg, ag), (a, ag, hg)):
                s = S[t]; s["pld"] += 1; s["gf"] += gf; s["ga"] += ga
                if gf > ga:   s["w"] += 1; s["pts"] += 3
                elif gf == ga: s["d"] += 1; s["pts"] += 1
                else:          s["l"] += 1
        order = sorted(TEAMS, key=lambda t: (-S[t]["pts"], -S[t]["gf"],
                                             -(S[t]["gf"] - S[t]["ga"]), -S[t]["w"], t))
        for i, t in enumerate(order):
            history[t].append(i + 1)
    final = [[i + 1, t, S[t]["pld"], S[t]["w"], S[t]["d"], S[t]["l"],
              S[t]["gf"], S[t]["ga"], S[t]["pts"]] for i, t in enumerate(order)]
    return history, final


def team_matches(rounds=None):
    """{팀: [{round, opp, ha, gf, ga, res}, ...]}  — 라운드 순 정렬"""
    rounds = rounds if rounds is not None else load()
    out = {t: [] for t in TEAMS}
    for rd in sorted(rounds, key=int):
        for h, hg, a, ag in rounds[rd]:
            for t, o, gf, ga, ha in ((h, a, hg, ag, "홈"), (a, h, ag, hg, "원정")):
                out[t].append({"round": int(rd), "opp": o, "ha": ha, "gf": gf, "ga": ga,
                               "res": "승" if gf > ga else ("무" if gf == ga else "패")})
    return out


if __name__ == "__main__":
    hist, fin = compute_positions()
    for row in fin:
        print(f"{row[0]:2} {row[1]:3} {row[2]:2}  {row[3]:2}-{row[4]:2}-{row[5]:2}  "
              f"{row[6]:2}:{row[7]:2}  {row[8]:2}점")
    print("\n인천 순위 추이:", hist["인천"])
