-- {"query": "9016.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2013, "output_tokens": 2497} 

WITH TopUsers AS (
    SELECT
        u.Id,
        u.DisplayName,
        u.Reputation,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.Id) AS UserRank
    FROM Users u
    WHERE u.Reputation > 1000
),
PostStats AS (
    SELECT
        p.Id               AS PostId,
        COUNT(DISTINCT c.Id)                             AS CommentCount,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        AVG(LENGTH(p.Body) - LENGTH(REPLACE(p.Body, '<', ''))) OVER () AS AvgBodyTags,
        MAX(v.CreationDate)                              AS LastVoteDate
    FROM Posts p
    LEFT JOIN Comments c ON c.PostId = p.Id
    LEFT JOIN Votes v    ON v.PostId = p.Id
    GROUP BY p.Id
),
FilteredPosts AS (
    SELECT
        p.*,
        ps.CommentCount,
        ps.UpVotes,
        ps.DownVotes,
        ps.AvgBodyTags,
        ps.LastVoteDate
    FROM Posts p
    JOIN PostStats ps ON ps.PostId = p.Id
    WHERE p.Score IS NOT NULL
      AND (ps.UpVotes - ps.DownVotes) > (
          SELECT COALESCE(AVG(v2.BountyAmount),0)
          FROM Votes v2
          WHERE v2.VoteTypeId = 8
      )
)
SELECT DISTINCT
    fp.Id                                         AS PostId,
    COALESCE(fp.Title, CONCAT('Answer to #', fp.ParentId)) AS TitleOrAnswer,
    SUBSTRING(fp.Body, 1, 100) || '...'           AS Snippet,
    tu.DisplayName                                AS TopUser,
    tu.UserRank,
    fp.CommentCount,
    fp.UpVotes - fp.DownVotes                     AS NetVotes,
    DATE_PART('day', NOW() - fp.CreationDate)     AS DaysOld,
    CASE
      WHEN fp.ViewCount > 10000                    THEN 'Hot'
      WHEN fp.ViewCount BETWEEN 1000 AND 10000     THEN 'Warm'
      ELSE 'Cold'
    END                                           AS Popularity,
    COALESCE((
      SELECT STRING_AGG(t.TagName, '|')
      FROM unnest(
             string_to_array(
               substring(fp.Tags,2,length(fp.Tags)-2)
             , '><')
           ) AS tag(token)
      JOIN Tags t ON t.TagName = tag.token
    ), '')                                        AS TagList,
    EXISTS (
      SELECT 1
      FROM Badges b
      WHERE b.UserId = fp.OwnerUserId
        AND b.Class = 1
    )                                             AS HasGoldBadge
FROM FilteredPosts fp
LEFT JOIN TopUsers tu      ON tu.Id = fp.OwnerUserId
FULL OUTER JOIN Users u2    ON u2.Id = fp.LastEditorUserId
WHERE fp.AvgBodyTags > NULLIF(fp.CommentCount, 0)
  AND fp.LastVoteDate > fp.CreationDate

UNION

SELECT
    p.Id,
    p.Title,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    NULL,
    FALSE
FROM Posts p
WHERE NOT EXISTS (
    SELECT 1
    FROM Votes v
    WHERE v.PostId = p.Id
)

INTERSECT

SELECT
    fp2.Id,
    fp2.TitleOrAnswer,
    fp2.Snippet,
    fp2.TopUser,
    fp2.UserRank,
    fp2.CommentCount,
    fp2.NetVotes,
    fp2.DaysOld,
    fp2.Popularity,
    fp2.TagList,
    fp2.HasGoldBadge
FROM FilteredPosts fp2

ORDER BY NetVotes DESC, DaysOld ASC
LIMIT 100;
