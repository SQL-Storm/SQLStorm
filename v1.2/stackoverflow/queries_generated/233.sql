-- {"query": "233.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1424} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 AS Level
    FROM Tags t
    WHERE t.IsModeratorOnly = 0 AND t.IsRequired = 0

    UNION ALL

    SELECT
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        r.Level + 1
    FROM Tags t2
    JOIN Posts p ON p.Tags LIKE '%' || '<' || t2.TagName || '>' || '%'
    JOIN RecursiveTagHierarchy r ON p.Id = r.ExcerptPostId
    WHERE r.Level < 3
),
UserBadgeStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COALESCE(SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END), 0) AS TagBasedBadges,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate) AS UserRank
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    WHERE u.Reputation > 1000
    GROUP BY u.Id, u.DisplayName
),
PostAnswerStats AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate AS QuestionCreation,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        a.Id AS AnswerId,
        a.OwnerUserId AS AnswerOwnerUserId,
        a.Score AS AnswerScore,
        a.CreationDate AS AnswerCreation,
        a.ParentId,
        ROW_NUMBER() OVER (PARTITION BY q.Id ORDER BY a.Score DESC, a.CreationDate) AS AnswerRank,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = q.Id) AS QuestionComments,
        (SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.Id) AS AnswerComments,
        EXISTS (
            SELECT 1 FROM Votes v WHERE v.PostId = q.Id AND v.VoteTypeId = 6
        ) AS HasCloseVotes
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
),
TopQuestionsWithAnswers AS (
    SELECT
        pas.QuestionId,
        pas.Title,
        pas.OwnerUserId,
        pas.QuestionCreation,
        pas.QuestionScore,
        pas.ViewCount,
        pas.AnswerCount,
        pas.AnswerId,
        pas.AnswerOwnerUserId,
        pas.AnswerScore,
        pas.AnswerCreation,
        pas.AnswerRank,
        pas.QuestionComments,
        pas.AnswerComments,
        pas.HasCloseVotes,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ub.TagBasedBadges,
        ub.UserRank
    FROM PostAnswerStats pas
    LEFT JOIN UserBadgeStats ub ON ub.UserId = pas.OwnerUserId
    WHERE pas.AnswerRank = 1 OR pas.AnswerRank IS NULL
),
AggregatedVotes AS (
    SELECT
        p.Id AS PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS UpVotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS DownVotes,
        SUM(CASE WHEN v.VoteTypeId = 5 THEN 1 ELSE 0 END) AS FavoriteVotes,
        SUM(COALESCE(v.BountyAmount, 0)) AS TotalBounty
    FROM Posts p
    LEFT JOIN Votes v ON v.PostId = p.Id
    GROUP BY p.Id
),
FinalResult AS (
    SELECT
        tqwa.QuestionId,
        tqwa.Title,
        tqwa.QuestionCreation,
        tqwa.QuestionScore,
        tqwa.ViewCount,
        tqwa.AnswerCount,
        tqwa.AnswerId,
        tqwa.AnswerScore,
        tqwa.AnswerCreation,
        tqwa.QuestionComments,
        tqwa.AnswerComments,
        tqwa.HasCloseVotes,
        tqwa.GoldBadges,
        tqwa.SilverBadges,
        tqwa.BronzeBadges,
        tqwa.TagBasedBadges,
        tqwa.UserRank,
        av.UpVotes,
        av.DownVotes,
        av.FavoriteVotes,
        av.TotalBounty,
        -- Complex string expression: concatenated tag list from question tags
        COALESCE(
            (
                SELECT STRING_AGG(DISTINCT TRIM(BOTH '<>' FROM unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><'))), ', ')
                FROM Posts p2
                WHERE p2.Id = tqwa.QuestionId
            ), ''
        ) AS TagList,
        -- Window function: rank questions by score partitioned by user rank bucket
        RANK() OVER (PARTITION BY (tqwa.UserRank / 100) ORDER BY tqwa.QuestionScore DESC) AS ScoreRankInUserBucket,
        -- NULL logic: check if accepted answer exists and is recent
        CASE
            WHEN EXISTS (
                SELECT 1 FROM Posts a WHERE a.Id = (SELECT AcceptedAnswerId FROM Posts WHERE Id = tqwa.QuestionId) AND a.CreationDate > (NOW() - INTERVAL '30 days')
            ) THEN 'Recent Accepted Answer'
            ELSE 'No Recent Accepted Answer'
        END AS AcceptedAnswerRecency,
        -- Correlated subquery: count of distinct users who commented on question or top answer
        (
            SELECT COUNT(DISTINCT COALESCE(c.UserId, -1))
            FROM Comments c
            WHERE c.PostId = tqwa.QuestionId
               OR c.PostId = tqwa.AnswerId
        ) AS DistinctCommenters
    FROM TopQuestionsWithAnswers tqwa
    LEFT JOIN AggregatedVotes av ON av.PostId = tqwa.QuestionId
)
SELECT *
FROM FinalResult
WHERE
    (QuestionScore > 10 OR AnswerScore > 5)
    AND (ViewCount > 1000 OR AnswerCount > 3)
    AND (GoldBadges + SilverBadges + BronzeBadges) > 0
ORDER BY UserRank, ScoreRankInUserBucket, QuestionCreation DESC
LIMIT 100;
