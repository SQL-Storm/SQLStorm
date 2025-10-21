-- {"query": "340.sql", "dataset": "stackoverflow", "version": "v1.4", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 32768, "reasoning": "high", "input_tokens": 2026, "output_tokens": 23583} 
WITH
  user_base AS (
    SELECT u.Id AS UserId,
           u.DisplayName,
           COALESCE(u.Location, '') AS Location
    FROM Users u
  ),
  post_totals AS (
    SELECT p.OwnerUserId AS UserId,
           COUNT(*) AS PostCount,
           COALESCE(SUM(p.Score), 0) AS ScoreSum,
           MAX(p.LastActivityDate) AS LastActiveDate
    FROM Posts p
    GROUP BY p.OwnerUserId
  ),
  vote_totals AS (
    SELECT p.OwnerUserId AS UserId,
           SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
           SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.OwnerUserId
  ),
  link_totals AS (
    SELECT p.OwnerUserId AS UserId,
           COUNT(*) AS RelatedLinks
    FROM Posts p
    LEFT JOIN PostLinks pl ON pl.PostId = p.Id
    GROUP BY p.OwnerUserId
  )
SELECT
  u.UserId,
  u.DisplayName,
  u.Location,
  COALESCE(pt.PostCount, 0) AS PostCount,
  COALESCE(pt.ScoreSum, 0) AS ScoreSum,
  COALESCE(vt.UpVotes, 0) AS UpVotes,
  COALESCE(vt.DownVotes, 0) AS DownVotes,
  (COALESCE(vt.UpVotes, 0) - COALESCE(vt.DownVotes, 0)) AS NetVotes,
  COALESCE(lt.RelatedLinks, 0) AS RelatedLinks,
  COALESCE((
     SELECT tt.TagName
     FROM Posts pp
     CROSS JOIN LATERAL unnest(string_to_array(substring(COALESCE(pp.Tags, ''), 2, greatest(length(COALESCE(pp.Tags, '')) - 2, 0)), '><')) AS tt(TagName)
     WHERE pp.OwnerUserId = u.UserId AND pp.PostTypeId = 1
     GROUP BY tt.TagName
     ORDER BY COUNT(*) DESC
     LIMIT 1
  ), '') AS TopTagName,
  DENSE_RANK() OVER (
     ORDER BY (COALESCE(vt.UpVotes, 0) - COALESCE(vt.DownVotes, 0)) DESC,
              COALESCE(pt.ScoreSum, 0) DESC
  ) AS Rank
FROM user_base u
LEFT JOIN post_totals pt ON pt.UserId = u.UserId
LEFT JOIN vote_totals vt ON vt.UserId = u.UserId
LEFT JOIN link_totals lt ON lt.UserId = u.UserId
ORDER BY Rank
LIMIT 100;