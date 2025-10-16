-- {"query": "5013.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1186} 
WITH MostViewedTagQuestions AS (
    SELECT
        unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) AS TagName,
        p.Id AS QuestionId,
        p.ViewCount,
        ROW_NUMBER() OVER (PARTITION BY unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) ORDER BY p.ViewCount DESC) AS rn
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1
        AND p.Tags IS NOT NULL
),
UserBadgeCounts AS (
    SELECT
        u.Id AS UserId,
        COUNT(CASE WHEN b.Class = 1 THEN 1 END) AS GoldBadges,
        COUNT(CASE WHEN b.Class = 2 THEN 1 END) AS SilverBadges,
        COUNT(CASE WHEN b.Class = 3 THEN 1 END) AS BronzeBadges,
        COUNT(*) AS TotalBadges
    FROM
        Users u
        LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY
        u.Id
),
ActiveCommenters AS (
    SELECT
        c.UserId,
        COUNT(*) AS CommentCount,
        AVG(c.Score) AS AvgCommentScore
    FROM
        Comments c
    WHERE
        c.UserId IS NOT NULL
    GROUP BY
        c.UserId
    HAVING
        COUNT(*) > 50
),
EditorActivity AS (
    SELECT
        ph.UserId,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId IN (4,5,6)) AS EditCount,
        COUNT(*) FILTER (WHERE ph.PostHistoryTypeId = 10) AS CloseCount,
        COUNT(*) AS HistoryEvents
    FROM
        PostHistory ph
    WHERE
        ph.UserId IS NOT NULL
    GROUP BY
        ph.UserId
),
PopularAnswers AS (
    SELECT
        p.ParentId AS QuestionId,
        p.Id AS AnswerId,
        p.Score AS AnswerScore,
        u.DisplayName AS AnswerOwner,
        ROW_NUMBER() OVER (PARTITION BY p.ParentId ORDER BY p.Score DESC, p.CreationDate ASC) AS rn
    FROM
        Posts p
        JOIN Users u ON u.Id = p.OwnerUserId
    WHERE
        p.PostTypeId = 2
        AND p.Score > 0
),
TopLinkedQuestions AS (
    SELECT
        pl.RelatedPostId AS QuestionId,
        COUNT(*) AS LinkCount
    FROM
        PostLinks pl
        JOIN Posts p ON pl.RelatedPostId = p.Id AND p.PostTypeId = 1
    WHERE
        pl.LinkTypeId = 1 -- Linked
    GROUP BY
        pl.RelatedPostId
    HAVING
        COUNT(*) > 5
)
SELECT
    tq.TagName,
    tq.QuestionId,
    p.Title AS QuestionTitle,
    tq.ViewCount,
    t.Count AS TagTotalCount,
    t.IsModeratorOnly,
    t.IsRequired,
    COALESCE(ta.LinkCount, 0) AS TotalLinks,
    pa.AnswerId AS TopAnswerId,
    pa.AnswerScore AS TopAnswerScore,
    pa.AnswerOwner AS TopAnswerOwner,
    u.Id AS OwnerUserId,
    u.DisplayName AS OwnerName,
    u.Reputation,
    ub.GoldBadges, ub.SilverBadges, ub.BronzeBadges, ub.TotalBadges,
    ac.CommentCount, ac.AvgCommentScore,
    ea.EditCount, ea.CloseCount, ea.HistoryEvents,
    CASE
        WHEN u.Location IS NULL THEN 'Location Unknown'
        WHEN u.Location ILIKE '%USA%' THEN 'USA'
        WHEN u.Location ILIKE '%India%' THEN 'India'
        ELSE u.Location
    END AS NormalizedLocation,
    CASE
        WHEN p.ViewCount > 10000 THEN 'Very High'
        WHEN p.ViewCount > 1000 THEN 'High'
        WHEN p.ViewCount > 100 THEN 'Medium'
        ELSE 'Low'
    END AS PopularityBucket,
    p.CreationDate,
    (SELECT COUNT(*) FROM Answers a WHERE a.PostTypeId = 2 AND a.ParentId = tq.QuestionId) AS NumAnswers,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = tq.QuestionId) AS NumComments,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = tq.QuestionId AND v.VoteTypeId = 2) AS Upvotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = tq.QuestionId AND v.VoteTypeId = 3) AS Downvotes
FROM
    MostViewedTagQuestions tq
    JOIN Posts p ON tq.QuestionId = p.Id
    JOIN Tags t ON tq.TagName = t.TagName
    LEFT JOIN TopLinkedQuestions ta ON tq.QuestionId = ta.QuestionId
    LEFT JOIN PopularAnswers pa ON pa.QuestionId = tq.QuestionId AND pa.rn = 1
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN UserBadgeCounts ub ON u.Id = ub.UserId
    LEFT JOIN ActiveCommenters ac ON ac.UserId = u.Id
    LEFT JOIN EditorActivity ea ON ea.UserId = u.Id
WHERE
    tq.rn = 1
    AND p.Score >= 0
    AND (
        pa.AnswerScore IS NULL OR
        pa.AnswerScore > (SELECT AVG(Score) FROM Posts ap WHERE ap.PostTypeId = 2 AND ap.ParentId = tq.QuestionId)
    )
ORDER BY
    t.Count DESC NULLS LAST,
    tq.ViewCount DESC
LIMIT 100;