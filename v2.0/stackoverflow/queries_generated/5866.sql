-- {"query": "5866.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 786} 
WITH recent_user_activity AS (
  SELECT
    u.Id AS UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    u.LastAccessDate,
    u.Location,
    u.AboutMe,
    u.Views,
    u.UpVotes,
    u.DownVotes,
    u.ProfileImageUrl,
    u.EmailHash,
    u.AccountId,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionCount,
    COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswerCount,
    MAX(p.CreationDate) AS LastPostDate
  FROM Users u
  LEFT JOIN Posts p ON p.OwnerUserId = u.Id
  GROUP BY
    u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate,
    u.Location, u.AboutMe, u.Views, u.UpVotes, u.DownVotes,
    u.ProfileImageUrl, u.EmailHash, u.AccountId
),
badge_scores AS (
  SELECT
    b.UserId,
    SUM(CASE WHEN b.Class = 1 THEN 1000 ELSE 100 END) AS badge_score
  FROM Badges b
  GROUP BY b.UserId
),
top_users AS (
  SELECT
    r.UserId,
    r.DisplayName,
    r.Reputation,
    r.LastPostDate,
    r.QuestionCount,
    r.AnswerCount,
    COALESCE(b.badge_score, 0) AS badge_score,
    (r.Reputation * 2 + r.QuestionCount * 5 + r.AnswerCount * 3 + COALESCE(b.badge_score, 0)) AS composite_rank
  FROM recent_user_activity r
  LEFT JOIN badge_scores b ON b.UserId = r.UserId
),
activity_diff AS (
  SELECT
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.LastPostDate,
    tu.QuestionCount,
    tu.AnswerCount,
    tu.badge_score,
    tu.composite_rank,
    -- Correlated subquery example: difference in last edit date vs last activity
    (SELECT MAX(ph.CreationDate)
     FROM PostHistory ph
     WHERE ph.PostId IN (SELECT Id FROM Posts WHERE OwnerUserId = tu.UserId)
       AND ph.PostHistoryTypeId = 16) AS LastCommunityOwnedDate,
    -- Window function over recent users
    ROW_NUMBER() OVER (ORDER BY tu.composite_rank DESC, tu.LastPostDate DESC) AS rank_within_group
  FROM top_users tu
  ORDER BY composite_rank DESC
  LIMIT 50
)
SELECT
  ad.UserId,
  ad.DisplayName,
  ad.Reputation,
  ad.LastPostDate,
  ad.QuestionCount,
  ad.AnswerCount,
  ad.badge_score,
  ad.composite_rank,
  ad.LastCommunityOwnedDate,
  ad.rank_within_group
FROM activity_diff ad
LEFT JOIN Posts p ON p.OwnerUserId = ad.UserId
LEFT JOIN Comments c ON c.UserId = ad.UserId
WHERE ad.LastPostDate >= (CURRENT_DATE - INTERVAL '365 days')
  AND (ad.Reputation > 1000 OR ad.badge_score > 1000)
  AND c.Id IS NULL -- example predicate involving NULL logic
GROUP BY
  ad.UserId, ad.DisplayName, ad.Reputation, ad.LastPostDate,
  ad.QuestionCount, ad.AnswerCount, ad.badge_score, ad.composite_rank,
  ad.LastCommunityOwnedDate, ad.rank_within_group
HAVING COUNT(p.Id) > 0
ORDER BY ad.composite_rank DESC
OFFSET 0 ROWS
FETCH FIRST 50 ROWS ONLY;