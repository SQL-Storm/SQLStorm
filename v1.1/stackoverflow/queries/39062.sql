-- {"query": "39062.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 3886} 
WITH TagUsage AS (
    SELECT
        unnest(
            string_to_array(
                substring(p.Tags, 2, length(p.Tags) - 2),
                '><'
            )
        ) AS TagName,
        p.Id AS QuestionId
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
),
TagMetrics AS (
    SELECT
        tu.TagName,
        COUNT(*)                                AS QuestionCount,
        COUNT(c.Id)                             AS CommentCount,
        AVG(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS AvgUpVoteRatio,
        AVG(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS AvgDownVoteRatio,
        ROW_NUMBER() OVER (ORDER BY COUNT(*) DESC)      AS TagRank
    FROM TagUsage tu
    LEFT JOIN Comments c ON c.PostId = tu.QuestionId
    LEFT JOIN Votes    v ON v.PostId = tu.QuestionId
    GROUP BY tu.TagName
    HAVING COUNT(*) > 500
),
AnswerersByTag AS (
    SELECT
        tu.TagName,
        p.OwnerUserId                       AS UserId,
        COUNT(*)                            AS AnswersCount,
        AVG(p.Score)                        AS AvgScore,
        ROW_NUMBER() OVER (
            PARTITION BY tu.TagName
            ORDER BY COUNT(*) DESC
        )                                  AS AnswererRank
    FROM TagUsage tu
    JOIN Posts p
      ON p.ParentId = tu.QuestionId
     AND p.PostTypeId = 2
    GROUP BY tu.TagName, p.OwnerUserId
),
UserActivity AS (
    SELECT
        u.Id                               AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p1.Id) FILTER (WHERE p1.PostTypeId = 1) AS Questions,
        COUNT(DISTINCT p2.Id) FILTER (WHERE p2.PostTypeId = 2) AS Answers,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END)       AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END)       AS DownVotes,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC)          AS UserRank
    FROM Users u
    LEFT JOIN Posts p1 ON p1.OwnerUserId = u.Id
    LEFT JOIN Posts p2 ON p2.OwnerUserId = u.Id
    LEFT JOIN Votes v   ON v.PostId = p2.Id
    GROUP BY u.Id, u.DisplayName, u.Reputation
),
BadgeCounts AS (
    SELECT
        b.UserId,
        b.Name           AS BadgeName,
        COUNT(*)         AS BadgeCount,
        ROW_NUMBER() OVER (
            PARTITION BY b.UserId
            ORDER BY COUNT(*) DESC
        )                AS BadgeRank
    FROM Badges b
    GROUP BY b.UserId, b.Name
)
SELECT
    tm.TagRank,
    tm.TagName,
    tm.QuestionCount,
    tm.CommentCount,
    tm.AvgUpVoteRatio,
    tm.AvgDownVoteRatio,
    abt.AnswersCount,
    abt.AvgScore,
    ua.DisplayName    AS TopAnswerer,
    ua.Questions,
    ua.Answers,
    ua.UpVotes,
    ua.DownVotes,
    bc.BadgeName,
    bc.BadgeCount
FROM TagMetrics tm
LEFT JOIN AnswerersByTag abt
  ON abt.TagName = tm.TagName
 AND abt.AnswererRank = 1
LEFT JOIN UserActivity ua
  ON ua.UserId = abt.UserId
LEFT JOIN BadgeCounts bc
  ON bc.UserId = ua.UserId
 AND bc.BadgeRank = 1
ORDER BY tm.TagRank, ua.UserRank;