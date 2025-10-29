-- {"query": "2554.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1871} 

WITH RecursiveTagHierarchy AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        ARRAY[t.Id] AS Ancestors
    FROM Tags t
    WHERE t.IsRequired = 1

    UNION ALL

    SELECT
        child.Id,
        child.TagName,
        child.Count,
        parent.Ancestors || child.Id
    FROM Tags child
    JOIN PostLinks pl ON pl.PostId = child.WikiPostId
    JOIN RecursiveTagHierarchy parent ON pl.RelatedPostId = parent.WikiPostId
    WHERE NOT child.Id = ANY(parent.Ancestors)
),

UserBadgeCounts AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        COALESCE(SUM(CASE WHEN b.TagBased = 1 THEN 1 ELSE 0 END), 0) AS TagBasedBadges,
        ROW_NUMBER() OVER (ORDER BY u.Reputation DESC, u.CreationDate) AS RepRank
    FROM Users u
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),

QuestionAnswerAggregates AS (
    SELECT
        q.Id AS QuestionId,
        q.Title,
        q.CreationDate AS QuestionDate,
        q.OwnerUserId,
        q.Score AS QuestionScore,
        q.ViewCount,
        q.Tags,
        COUNT(a.Id) AS AnswerCount,
        AVG(a.Score) AS AvgAnswerScore,
        MAX(a.Score) AS MaxAnswerScore,
        SUM((SELECT COUNT(*) FROM Comments c WHERE c.PostId = a.Id)) AS TotalAnswerComments,
        -- Correlated subquery to find if any answer has accepted answer votes
        EXISTS (
            SELECT 1 FROM Votes v
            WHERE v.PostId = a.Id AND v.VoteTypeId = 1
        ) AS HasAcceptedAnswerVote
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
    GROUP BY q.Id, q.Title, q.CreationDate, q.OwnerUserId, q.Score, q.ViewCount, q.Tags
),

LastEditPerPost AS (
    SELECT
        ph.PostId,
        MAX(ph.CreationDate) AS LastEditDate
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 14) -- Edits and suggested edits
    GROUP BY ph.PostId
),

PostsWithLastEdit AS (
    SELECT
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.CreationDate,
        p.PostTypeId,
        p.Tags,
        p.ViewCount,
        COALESCE(le.LastEditDate, p.LastEditDate) AS LastEditDateEffective
    FROM Posts p
    LEFT JOIN LastEditPerPost le ON le.PostId = p.Id
),

UserActivityRankings AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId IN (1, 2)) AS TotalPosts,
        COUNT(DISTINCT c.Id) AS TotalComments,
        COUNT(DISTINCT v.Id) FILTER (WHERE v.VoteTypeId IN (2,3)) AS VotesCast,
        COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 AND p.AcceptedAnswerId IS NOT NULL THEN p.Id END) AS QuestionsWithAcceptedAnswers,
        ROW_NUMBER() OVER (PARTITION BY 1 ORDER BY COUNT(DISTINCT p.Id) DESC) AS PostRank,
        ROW_NUMBER() OVER (PARTITION BY 1 ORDER BY COUNT(DISTINCT c.Id) DESC) AS CommentRank,
        ROW_NUMBER() OVER (PARTITION BY 1 ORDER BY COUNT(DISTINCT v.Id) DESC) AS VoteRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Comments c ON c.UserId = u.Id
    LEFT JOIN Votes v ON v.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),

FinalQuestionDetails AS (
    SELECT
        q.QuestionId,
        q.Title,
        q.QuestionDate,
        q.QuestionScore,
        q.ViewCount,
        q.Tags,
        q.AnswerCount,
        q.AvgAnswerScore,
        q.MaxAnswerScore,
        q.TotalAnswerComments,
        q.HasAcceptedAnswerVote,
        u.DisplayName AS QuestionOwner,
        ub.GoldBadges,
        ub.SilverBadges,
        ub.BronzeBadges,
        ua.TotalPosts,
        ua.TotalComments,
        ua.VotesCast,
        ua.QuestionsWithAcceptedAnswers
    FROM QuestionAnswerAggregates q
    LEFT JOIN Users u ON u.Id = q.OwnerUserId
    LEFT JOIN UserBadgeCounts ub ON ub.UserId = u.Id
    LEFT JOIN UserActivityRankings ua ON ua.UserId = u.Id
    WHERE q.AnswerCount > 0
),

DuplicateLinks AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        pt1.Name AS PostType,
        pt2.Name AS RelatedPostType
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId AND lt.Name = 'Duplicate'
    JOIN Posts p1 ON p1.Id = pl.PostId
    JOIN Posts p2 ON p2.Id = pl.RelatedPostId
    JOIN PostTypes pt1 ON pt1.Id = p1.PostTypeId
    JOIN PostTypes pt2 ON pt2.Id = p2.PostTypeId
),

UnionedPostSets AS (
    SELECT Id, Title, OwnerUserId, Score, Posts.PostTypeId, CreationDate FROM Posts WHERE PostTypeId = 1 -- Questions
    UNION ALL
    SELECT Id, Title, OwnerUserId, Score, Posts.PostTypeId, CreationDate FROM Posts WHERE PostTypeId = 2 -- Answers
),

WindowedPostScores AS (
    SELECT
        Id,
        Title,
        OwnerUserId,
        Score,
        PostTypeId,
        CreationDate,
        SUM(Score) OVER (PARTITION BY OwnerUserId ORDER BY CreationDate ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS CumulativeScore,
        RANK() OVER (PARTITION BY PostTypeId ORDER BY Score DESC, CreationDate) AS ScoreRank
    FROM UnionedPostSets
)

SELECT
    fqd.QuestionId,
    fqd.Title AS QuestionTitle,
    fqd.QuestionDate,
    fqd.QuestionScore,
    fqd.ViewCount,
    fqd.Tags,
    fqd.AnswerCount,
    ROUND(fqd.AvgAnswerScore::NUMERIC, 2) AS AverageAnswerScore,
    fqd.MaxAnswerScore,
    fqd.TotalAnswerComments,
    fqd.HasAcceptedAnswerVote,
    fqd.QuestionOwner,
    fqd.GoldBadges,
    fqd.SilverBadges,
    fqd.BronzeBadges,
    fqd.TotalPosts,
    fqd.TotalComments,
    fqd.VotesCast,
    fqd.QuestionsWithAcceptedAnswers,
    dl.PostId AS DuplicateQuestionId,
    dl.RelatedPostId AS OriginalQuestionId,
    dl.PostType AS DuplicatePostType,
    dl.RelatedPostType AS OriginalPostType,
    wh.CumulativeScore,
    wh.ScoreRank,
    -- String and NULL logic with complicated expressions
    CASE
        WHEN fqd.Tags IS NULL OR LENGTH(TRIM(fqd.Tags)) = 0 THEN '[no tags]'
        ELSE CONCAT(
            'Tags: ',
            REGEXP_REPLACE(fqd.Tags, '[<>{}\s]+', '', 'g')
        )
    END AS CleanedTags,
    CASE 
        WHEN fqd.QuestionScore < 0 THEN 'Negative score'
        WHEN fqd.QuestionScore = 0 THEN 'Neutral score'
        ELSE 'Positive score'
    END AS ScoreCategory,
    LENGTH(COALESCE(fqd.Title, '')) AS TitleLength,
    NULLIF(fqd.QuestionOwner, '') AS ValidOwnerName,
    (SELECT COUNT(*) FROM RecursiveTagHierarchy rth WHERE rth.TagName ILIKE '%sql%') AS SqlTagDepth
FROM FinalQuestionDetails fqd
LEFT JOIN DuplicateLinks dl ON dl.PostId = fqd.QuestionId
LEFT JOIN WindowedPostScores wh ON wh.Id = fqd.QuestionId
WHERE fqd.AnswerCount > 3
AND (fqd.ViewCount > 1000 OR fqd.QuestionScore > 10)
ORDER BY fqd.QuestionDate DESC, fqd.QuestionScore DESC
LIMIT 100;
