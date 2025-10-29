-- {"query": "3118.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-oss-120b", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2089, "output_tokens": 1499} 

WITH RECURSIVE tag_hierarchy AS (
    -- flatten tag strings into one row per tag for each question
    SELECT
        p.Id               AS QuestionId,
        TRIM(t)            AS Tag,
        1                  AS lvl
    FROM Posts p
    CROSS JOIN LATERAL regexp_split_to_table(
        COALESCE(p.Tags, ''),         -- string like "<tag1><tag2>"
        '><'
    ) AS t
    WHERE p.PostTypeId = 1                       -- only questions
      AND p.CreationDate >= now() - interval '1 year'
),
tag_stats AS (
    SELECT
        th.Tag,
        COUNT(DISTINCT th.QuestionId)                 AS QuestionsPerTag,
        SUM(p.Score)                                  AS TotalScore,
        AVG(p.ViewCount)                              AS AvgViews,
        MAX(p.CreationDate)                           AS LatestQuestion
    FROM tag_hierarchy th
    JOIN Posts p ON p.Id = th.QuestionId
    GROUP BY th.Tag
),
user_activity AS (
    SELECT
        u.Id                                 AS UserId,
        u.DisplayName,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsAsked,
        COUNT(p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersGiven,
        SUM(COALESCE(v.UpVotes,0) - COALESCE(v.DownVotes,0)) AS NetVotes,
        COUNT(b.Id) FILTER (WHERE b.Class = 1)   AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2)   AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3)   AS BronzeBadges,
        MAX(p.CreationDate)                     AS LastPostDate,
        ROW_NUMBER() OVER (PARTITION BY u.Id
                           ORDER BY COUNT(p.Id) DESC) AS activity_rank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN (
        SELECT
            p.OwnerUserId,
            SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Posts p
        JOIN Votes v ON v.PostId = p.Id
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        GROUP BY p.OwnerUserId
    ) v ON v.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
question_metrics AS (
    SELECT
        q.Id                                   AS QId,
        q.Title,
        q.Score,
        q.ViewCount,
        q.AnswerCount,
        COALESCE(a.AvgAnswerScore,0)           AS AvgAnswerScore,
        COALESCE(d.DupCount,0)                 AS DuplicateCount,
        COALESCE(vc.UpVotes,0)                 AS UpVoteCount,
        COALESCE(vc.DownVotes,0)               AS DownVoteCount,
        ROW_NUMBER() OVER (PARTITION BY t.Tag ORDER BY q.Score DESC, q.ViewCount DESC) AS RankInTag
    FROM Posts q
    LEFT JOIN LATERAL (
        SELECT AVG(p2.Score) AS AvgAnswerScore
        FROM Posts p2
        WHERE p2.PostTypeId = 2
          AND p2.ParentId = q.Id
    ) a ON TRUE
    LEFT JOIN LATERAL (
        SELECT COUNT(*) AS DupCount
        FROM PostLinks pl
        WHERE pl.LinkTypeId = 3                -- duplicate link
          AND pl.RelatedPostId = q.Id
    ) d ON TRUE
    LEFT JOIN LATERAL (
        SELECT
            SUM(CASE WHEN vt.Id = 2 THEN 1 ELSE 0 END) AS UpVotes,
            SUM(CASE WHEN vt.Id = 3 THEN 1 ELSE 0 END) AS DownVotes
        FROM Votes v
        JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
        WHERE v.PostId = q.Id
    ) vc ON TRUE
    LEFT JOIN tag_hierarchy t ON t.QuestionId = q.Id
    WHERE q.PostTypeId = 1
      AND q.CreationDate >= now() - interval '1 year'
),
combined AS (
    SELECT
        qm.QId,
        qm.Title,
        qm.Score,
        qm.ViewCount,
        qm.AnswerCount,
        qm.AvgAnswerScore,
        qm.DuplicateCount,
        qm.UpVoteCount,
        qm.DownVoteCount,
        th.Tag,
        ts.QuestionsPerTag,
        ts.TotalScore   AS TagTotalScore,
        ts.AvgViews     AS TagAvgViews,
        ua.UserId,
        ua.DisplayName,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.NetVotes,
        ua.GoldBadges,
        ua.SilverBadges,
        ua.BronzeBadges,
        ua.activity_rank,
        CASE
            WHEN qm.RankInTag <= 5 THEN 'Top5InTag'
            WHEN qm.RankInTag <= 20 THEN 'Top20InTag'
            ELSE 'Other'
        END AS TagRankCategory,
        COALESCE(NULLIF(qm.RankInTag,0), -1) AS RankInTag
    FROM question_metrics qm
    LEFT JOIN tag_stats ts ON ts.Tag = qm.Tag
    LEFT JOIN Users u ON u.Id = (SELECT OwnerUserId FROM Posts WHERE Id = qm.QId)
    LEFT JOIN user_activity ua ON ua.UserId = u.Id
)
SELECT *
FROM combined
WHERE (TagRankCategory = 'Top5InTag' AND ua.GoldBadges > 0)
   OR (TagRankCategory = 'Top20InTag' AND ua.NetVotes > 1000)
   OR (TagRankCategory = 'Other' AND qm.Score > 50)
ORDER BY Tag, RankInTag ASC, Score DESC
LIMIT 200;
