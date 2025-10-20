-- {"query": "337.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 20273} 
WITH base AS (
  SELECT
     u.Id,
     COALESCE(u.DisplayName, 'Unknown') AS DisplayName,
     u.Reputation,
     u.Views,
     u.UpVotes,
     u.DownVotes,
     u.WebsiteUrl,
     u.Location,
     u.AboutMe
  FROM Users u
  WHERE (COALESCE(u.WebsiteUrl, '') <> '' OR COALESCE(u.Location, '') <> '' OR COALESCE(u.AboutMe, '') <> '')
    AND u.Reputation > 0
),
per_user AS (
  SELECT
     b.Id,
     b.DisplayName,
     b.Reputation,
     b.Views,
     b.UpVotes,
     b.DownVotes,
     COALESCE(post.PostCount, 0) AS PostCount,
     COALESCE(comm.CommentCount, 0) AS CommentCount,
     COALESCE(bad.BadgeCount, 0) AS BadgeCount,
     post.LastActivityDate
  FROM base b
  LEFT JOIN LATERAL (
     SELECT COUNT(*) AS PostCount, MAX(p.LastActivityDate) AS LastActivityDate
     FROM Posts p
     WHERE p.OwnerUserId = b.Id
  ) AS post ON TRUE
  LEFT JOIN LATERAL (
     SELECT COUNT(*) AS CommentCount
     FROM Comments c
     WHERE c.UserId = b.Id
  ) AS comm ON TRUE
  LEFT JOIN LATERAL (
     SELECT COUNT(*) AS BadgeCount
     FROM Badges ba
     WHERE ba.UserId = b.Id
  ) AS bad ON TRUE
),
score AS (
  SELECT
     Id, DisplayName, Reputation, Views, UpVotes, DownVotes,
     PostCount, CommentCount, BadgeCount, LastActivityDate,
     (Reputation * 1.0 + Views * 0.01 + UpVotes * 2.0 - DownVotes * 1.5
      + BadgeCount * 5.0 + COALESCE(CommentCount,0) * 0.2 + COALESCE(PostCount,0) * 0.4) AS CompositeScore
  FROM per_user
),
ranked AS (
  SELECT s.*,
         ROW_NUMBER() OVER (ORDER BY CompositeScore DESC NULLS LAST) AS rn
  FROM score s
)
SELECT
   Id, DisplayName, Reputation, Views, UpVotes, DownVotes,
   PostCount, CommentCount, BadgeCount, LastActivityDate,
   CompositeScore,
   (DisplayName || ' | rep=' || Reputation::text || ' posts=' || PostCount::text ||
    ' last_act=' || COALESCE(TO_CHAR(LastActivityDate, 'YYYY-MM-DD HH24:MI:SS'), 'N/A')) AS Summary
FROM (
  SELECT * FROM ranked
  WHERE rn <= 200
  UNION ALL
  SELECT * FROM ranked
  WHERE LastActivityDate IS NOT NULL
) AS combined
ORDER BY CompositeScore DESC
LIMIT 300;