-- {"query": "4056.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1501} 

WITH RecursiveTagCounts AS (
    SELECT
        t.Id,
        t.TagName,
        t.Count,
        COALESCE(p.AnswerCount, 0) AS AnswerCount,
        COALESCE(p.ViewCount, 0) AS ViewCount,
        COALESCE(p.Score, 0) AS Score,
        ROW_NUMBER() OVER (ORDER BY t.Count DESC, t.TagName) AS TagRank
    FROM
        Tags t
        LEFT JOIN Posts p ON p.Id = t.ExcerptPostId AND p.PostTypeId = 1
    WHERE
        t.IsModeratorOnly = 0
),
UserBadgeStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(b.Id) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(b.Id) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        SUM(COALESCE(vb.VoteCount, 0)) AS TotalVotes
    FROM
        Users u
        LEFT JOIN Badges b ON u.Id = b.UserId
        LEFT JOIN (
            SELECT
                p.OwnerUserId,
                COUNT(v.Id) AS VoteCount
            FROM
                Posts p
                LEFT JOIN Votes v ON p.Id = v.PostId AND v.VoteTypeId IN (2, 3)
            WHERE
                p.OwnerUserId IS NOT NULL
            GROUP BY
                p.OwnerUserId
        ) vb ON u.Id = vb.OwnerUserId
    GROUP BY u.Id, u.DisplayName
),
TopPosts AS (
    SELECT 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags,
        p.AcceptedAnswerId,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC, p.ViewCount DESC) AS UserPostRank,
        COUNT(*) OVER (PARTITION BY p.OwnerUserId) AS UserPostCount,
        LAG(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PrevScore,
        LEAD(p.Score) OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS NextScore
    FROM
        Posts p
    WHERE
        p.PostTypeId = 1
        AND p.Score IS NOT NULL
        AND (p.Tags IS NOT NULL AND p.Tags <> '')
),
FilteredLinks AS (
    SELECT
        pl.PostId,
        pl.RelatedPostId,
        pl.LinkTypeId,
        pl.CreationDate,
        lt.Name AS LinkTypeName,
        q.Score AS QuestionScore,
        a.Score AS AnswerScore,
        q.ViewCount AS QuestionViewCount,
        a.ViewCount AS AnswerViewCount
    FROM
        PostLinks pl
        JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
        LEFT JOIN Posts q ON pl.PostId = q.Id AND q.PostTypeId = 1
        LEFT JOIN Posts a ON pl.RelatedPostId = a.Id AND a.PostTypeId = 2
    WHERE
        pl.LinkTypeId IN (1, 3)
),
CloseReasonAggregates AS (
    SELECT
        ph.PostId,
        crt.Name AS CloseReason,
        COUNT(*) AS CloseVotesCount,
        MAX(ph.CreationDate) AS LastCloseVoteDate
    FROM
        PostHistory ph
        JOIN CloseReasonTypes crt ON CAST(ph.Comment AS int) = crt.Id
    WHERE
        ph.PostHistoryTypeId = 10 -- Post Closed
        AND ph.Comment IS NOT NULL
    GROUP BY
        ph.PostId, crt.Name
),
UserActivityStats AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 1) AS QuestionsPosted,
        COUNT(DISTINCT p.Id) FILTER (WHERE p.PostTypeId = 2) AS AnswersPosted,
        COUNT(DISTINCT c.Id) AS CommentsMade,
        AVG(p.Score) FILTER (WHERE p.PostTypeId IN (1,2)) AS AvgPostScore,
        MAX(p.CreationDate) FILTER (WHERE p.PostTypeId IN (1,2)) AS LastPostDate,
        COUNT(ph.Id) FILTER (WHERE ph.PostHistoryTypeId IN (10,11)) AS TotalCloseReopenEvents
    FROM
        Users u
        LEFT JOIN Posts p ON u.Id = p.OwnerUserId
        LEFT JOIN Comments c ON u.Id = c.UserId
        LEFT JOIN PostHistory ph ON p.Id = ph.PostId
    GROUP BY
        u.Id, u.DisplayName
)
SELECT
    u.DisplayName AS User,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ua.QuestionsPosted,
    ua.AnswersPosted,
    ua.CommentsMade,
    ua.AvgPostScore,
    ua.LastPostDate,
    ub.TotalVotes,
    c.CloseReason,
    c.CloseVotesCount,
    c.LastCloseVoteDate,
    t.TagName,
    t.Count AS TagOccurrence,
    tp.Title AS TopQuestionTitle,
    tp.Score AS TopQuestionScore,
    tp.ViewCount AS TopQuestionViews,
    tp.UserPostCount,
    tp.PrevScore,
    tp.NextScore,
    CASE 
        WHEN tp.Tags IS NOT NULL AND tp.Tags LIKE '%<sql>%' THEN 'Contains SQL Tag'
        ELSE 'No SQL Tag'
    END AS SQLTagPresence,
    fl.LinkTypeName,
    fl.QuestionScore,
    fl.AnswerScore,
    fl.QuestionViewCount,
    fl.AnswerViewCount
FROM
    UserBadgeStats ub
    JOIN Users u ON u.Id = ub.UserId
    LEFT JOIN UserActivityStats ua ON u.Id = ua.UserId
    LEFT JOIN CloseReasonAggregates c ON c.PostId IN (
        SELECT p.Id FROM Posts p WHERE p.OwnerUserId = u.Id
    )
    LEFT JOIN RecursiveTagCounts t ON t.TagRank <= 10
    LEFT JOIN TopPosts tp ON tp.OwnerUserId = u.Id AND tp.UserPostRank = 1
    LEFT JOIN LATERAL (
        SELECT fl1.LinkTypeName, fl1.QuestionScore, fl1.AnswerScore, fl1.QuestionViewCount, fl1.AnswerViewCount
        FROM FilteredLinks fl1
        JOIN Posts p1 ON p1.Id = fl1.PostId
        WHERE p1.OwnerUserId = u.Id
        ORDER BY fl1.CreationDate DESC
        LIMIT 1
    ) fl ON TRUE
WHERE
    (ub.GoldBadges + ub.SilverBadges + ub.BronzeBadges) > 5
    AND ua.QuestionsPosted > 10
    AND ua.AvgPostScore > 5
    AND c.CloseVotesCount IS NOT NULL
ORDER BY
    ua.QuestionsPosted DESC,
    ub.GoldBadges DESC,
    tp.Score DESC
LIMIT 100;
