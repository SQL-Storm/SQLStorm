WITH RecursiveTags AS (
    SELECT
        p.Id AS PostId,
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><')) AS aTag
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1
),
PostsWithAcceptedAnswer AS (
    SELECT 
        q.Id AS QuestionId,
        a.Id AS AcceptedAnswerId,
        a.Score AS AcceptedAnswerScore,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC NULLS LAST, a.CreationDate DESC NULLS LAST) AS rn
    FROM Posts q
    LEFT JOIN Posts a ON a.Id = q.AcceptedAnswerId AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
),
BadgesUsage AS (
  SELECT
    b.UserId,
    b.Name,
    COALESCE(u.DisplayName, '') AS UserName,
    COUNT(*) AS badge_all_time,
    SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS gold,
    SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS silver,
    SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS bronze,
    MAX(b.Date) AS LastFavDate
  FROM Badges b
  LEFT JOIN Users u ON u.Id = b.UserId
  GROUP BY b.UserId, b.Name, u.DisplayName
)
SELECT
  -- example final select to use the CTEs; adapt as needed
  rt.PostId,
  rt.aTag,
  pwa.QuestionId,
  pwa.AcceptedAnswerId,
  pwa.AcceptedAnswerScore,
  pwa.rn,
  bu.UserId,
  bu.Name,
  bu.UserName,
  bu.badge_all_time,
  bu.gold,
  bu.silver,
  bu.bronze,
  bu.LastFavDate
FROM RecursiveTags rt
LEFT JOIN PostsWithAcceptedAnswer pwa ON pwa.QuestionId = rt.PostId
LEFT JOIN BadgesUsage bu ON bu.UserId = rt.PostId
;