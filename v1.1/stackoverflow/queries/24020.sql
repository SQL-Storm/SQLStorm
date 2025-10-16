WITH recent_posts AS (
    SELECT
        p.Id            AS PostId,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        COALESCE(v.Cnt, 0)    AS VoteCnt,
        COALESCE(c.Cnt, 0)    AS CommentCnt,
        string_to_array(substring(p.Tags, 2, length(p.Tags) - 2), '><') AS TagArray
    FROM Posts p
    LEFT JOIN (SELECT PostId, COUNT(*) AS Cnt FROM Votes GROUP BY PostId) v
           ON v.PostId = p.Id
    LEFT JOIN (SELECT PostId, COUNT(*) AS Cnt FROM Comments GROUP BY PostId) c
           ON c.PostId = p.Id
    WHERE p.PostTypeId = 1
      AND p.CreationDate >= CAST('2024-10-01 12:34:56' AS timestamp) - INTERVAL '30 days'
),
tag_stats AS (
    SELECT
        tag,
        SUM(pr.VoteCnt)      AS TotalVotes,
        AVG(pr.Score)        AS AvgScore,
        COUNT(DISTINCT pr.PostId) AS PostCount,
        MAX(pr.CreationDate) AS Latest
    FROM recent_posts pr,
         UNNEST(pr.TagArray) AS tag
    GROUP BY tag
    HAVING SUM(pr.VoteCnt) > 20
),
ranked_tags AS (
    SELECT ts.*,
           ROW_NUMBER() OVER (ORDER BY TotalVotes DESC) AS Rank
    FROM tag_stats ts
),
top_users AS (
    SELECT
        u.Id           AS UserId,
        u.DisplayName,
        SUM(p.Score)   AS TotalScore,
        COUNT(DISTINCT p.Id) AS QuestionCount,
        ROW_NUMBER() OVER (ORDER BY SUM(p.Score) DESC) AS Rank
    FROM Users u
    JOIN Posts p ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1
    GROUP BY u.Id, u.DisplayName
    HAVING SUM(p.Score) > 100
),
unbalanced_ranks AS (
    SELECT *
    FROM top_users
    WHERE Rank > 5 AND Rank < 10
)
SELECT
    rt.tag,
    rt.TotalVotes,
    rt.AvgScore,
    rt.PostCount,
    rt.Latest,
    tu.UserId,
    tu.DisplayName,
    tu.TotalScore,
    tu.QuestionCount,
    (SELECT COUNT(*)
     FROM Badges b
     WHERE b.Class = 1
       AND b.TagBased = TRUE
       AND b.Name = rt.tag
    ) AS GoldBadgeUsers,
    (SELECT MIN(p2.Score)
     FROM Posts p2
     WHERE p2.OwnerUserId = tu.UserId
       AND p2.PostTypeId = 1
    ) AS MinUserScore
FROM ranked_tags rt
JOIN top_users tu ON tu.Rank = 1
WHERE rt.Rank = 1

UNION ALL

SELECT
    NULL            AS tag,
    0               AS TotalVotes,
    0.0             AS AvgScore,
    0               AS PostCount,
    NULL            AS Latest,
    ub.UserId,
    ub.DisplayName,
    ub.TotalScore,
    ub.QuestionCount,
    0               AS GoldBadgeUsers,
    NULL            AS MinUserScore
FROM unbalanced_ranks ub
ORDER BY TotalVotes DESC NULLS LAST;