-- {"query": "39094.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "codex-mini-latest", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1972, "output_tokens": 3810} 

WITH
    TagSplits AS (
        SELECT
            p.Id        AS QuestionId,
            p.Title,
            unnest(
                string_to_array(
                    substring(p.Tags, 2, length(p.Tags) - 2),
                    '><'
                )
            )         AS TagName
        FROM Posts p
        WHERE p.PostTypeId = 1
    ),
    TopTags AS (
        SELECT
            TagName,
            count(*)   AS QuestionCount
        FROM TagSplits
        GROUP BY TagName
        ORDER BY QuestionCount DESC
        LIMIT 10
    ),
    UserAnswerStats AS (
        SELECT
            a.OwnerUserId                                    AS UserId,
            ts.TagName,
            count(*)                                         AS AnswerCount,
            avg(EXTRACT(EPOCH FROM (a.CreationDate - q.CreationDate))) AS AvgFirstResponseSec
        FROM Posts a
        JOIN Posts q
          ON q.Id = a.ParentId
         AND q.PostTypeId = 1
        JOIN TagSplits ts
          ON ts.QuestionId = q.Id
        WHERE a.PostTypeId = 2
          AND ts.TagName IN (SELECT TagName FROM TopTags)
        GROUP BY a.OwnerUserId, ts.TagName
    ),
    BadgeCounts AS (
        SELECT
            UserId,
            sum(CASE WHEN Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
            sum(CASE WHEN Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
            sum(CASE WHEN Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges
        FROM Badges
        GROUP BY UserId
    ),
    UserVoteStats AS (
        SELECT
            UserId,
            sum(CASE WHEN VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
            sum(CASE WHEN VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes
        WHERE UserId IS NOT NULL
        GROUP BY UserId
    ),
    UserCommentStats AS (
        SELECT
            UserId,
            count(*)                                    AS TotalComments
        FROM Comments
        WHERE UserId IS NOT NULL
        GROUP BY UserId
    ),
    UserEditStats AS (
        SELECT
            UserId,
            count(*) FILTER (WHERE PostHistoryTypeId IN (4,5,6,9)) AS TotalEdits
        FROM PostHistory
        WHERE UserId IS NOT NULL
        GROUP BY UserId
    ),
    UserRanked AS (
        SELECT
            UserId,
            TagName,
            AnswerCount,
            AvgFirstResponseSec,
            RANK() OVER (PARTITION BY TagName ORDER BY AnswerCount DESC) AS TagRank
        FROM UserAnswerStats
    )
SELECT
    ur.TagName,
    us.DisplayName,
    ur.TagRank,
    ur.AnswerCount,
    round(ur.AvgFirstResponseSec/3600, 2) AS AvgResponseHours,
    coalesce(bc.GoldBadges, 0)    AS GoldBadges,
    coalesce(bc.SilverBadges, 0)  AS SilverBadges,
    coalesce(bc.BronzeBadges, 0)  AS BronzeBadges,
    coalesce(uv.UpVotes, 0)       AS UpVotes,
    coalesce(uv.DownVotes, 0)     AS DownVotes,
    coalesce(uc.TotalComments, 0) AS TotalComments,
    coalesce(ues.TotalEdits, 0)   AS TotalEdits
FROM UserRanked ur
JOIN Users us ON us.Id = ur.UserId
LEFT JOIN BadgeCounts      bc  ON bc.UserId = us.Id
LEFT JOIN UserVoteStats    uv  ON uv.UserId = us.Id
LEFT JOIN UserCommentStats uc  ON uc.UserId = us.Id
LEFT JOIN UserEditStats    ues ON ues.UserId = us.Id
WHERE ur.TagRank <= 5
ORDER BY ur.TagName, ur.TagRank;
