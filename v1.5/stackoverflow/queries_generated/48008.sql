-- {"query": "48008.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 753} 
WITH UserPostActivity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    COUNT(DISTINCT p.Id) AS TotalPosts,
    SUM(CASE WHEN pt.Name = 'Question' THEN 1 ELSE 0 END) AS TotalQuestions,
    SUM(CASE WHEN pt.Name = 'Answer' THEN 1 ELSE 0 END) AS TotalAnswers,
    AVG(p.Score) AS AveragePostScore,
    MAX(p.CreationDate) AS LastPostDate
  FROM Users AS u
  JOIN Posts AS p
    ON u.Id = p.OwnerUserId
  JOIN PostTypes AS pt
    ON p.PostTypeId = pt.Id
  WHERE
    p.CreationDate >= DATE('now', '-1 year')
  GROUP BY
    u.Id,
    u.DisplayName
), UserBadgeActivity AS (
  SELECT
    b.UserId,
    COUNT(DISTINCT b.Id) AS TotalBadges,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
  FROM Badges AS b
  WHERE
    b.Date >= DATE('now', '-1 year')
  GROUP BY
    b.UserId
), UserVoteActivity AS (
  SELECT
    v.UserId,
    COUNT(DISTINCT v.Id) AS TotalVotes,
    SUM(CASE WHEN vt.Name = 'UpMod' THEN 1 ELSE 0 END) AS TotalUpVotes,
    SUM(CASE WHEN vt.Name = 'DownMod' THEN 1 ELSE 0 END) AS TotalDownVotes
  FROM Votes AS v
  JOIN VoteTypes AS vt
    ON v.VoteTypeId = vt.Id
  WHERE
    v.CreationDate >= DATE('now', '-1 year')
  GROUP BY
    v.UserId
)
SELECT
  upa.UserId,
  upa.DisplayName,
  upa.TotalPosts,
  upa.TotalQuestions,
  upa.TotalAnswers,
  upa.AveragePostScore,
  upa.LastPostDate,
  COALESCE(uba.TotalBadges, 0) AS TotalBadgesEarned,
  COALESCE(uba.GoldBadges, 0) AS GoldBadgesEarned,
  COALESCE(uba.SilverBadges, 0) AS SilverBadgesEarned,
  COALESCE(uba.BronzeBadges, 0) AS BronzeBadgesEarned,
  COALESCE(uva.TotalVotes, 0) AS TotalVotesCast,
  COALESCE(uva.TotalUpVotes, 0) AS TotalUpVotesCast,
  COALESCE(uva.TotalDownVotes, 0) AS TotalDownVotesCast
FROM UserPostActivity AS upa
LEFT JOIN UserBadgeActivity AS uba
  ON upa.UserId = uba.UserId
LEFT JOIN UserVoteActivity AS uva
  ON upa.UserId = uva.UserId
ORDER BY
  upa.AveragePostScore DESC,
  upa.TotalQuestions DESC,
  upa.TotalAnswers DESC,
  upa.TotalPosts DESC
LIMIT 1000;