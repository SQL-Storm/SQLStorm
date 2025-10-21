-- {"query": "35083.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 1986, "output_tokens": 766} 
WITH RecentActiveUsers AS (
    SELECT 
        u.Id AS UserId, 
        u.DisplayName, 
        u.Reputation,
        u.LastAccessDate,
        COUNT(p.Id) AS TotalPosts,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END), 0) AS TotalQuestions,
        COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END), 0) AS TotalAnswers
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    WHERE u.LastAccessDate >= NOW() - INTERVAL '30 days'
    GROUP BY u.Id, u.DisplayName, u.Reputation, u.LastAccessDate
    HAVING COUNT(p.Id) > 10
),
HotQuestions AS (
    SELECT 
        q.Id AS QuestionId,
        q.Title,
        q.Score,
        q.ViewCount,
        q.OwnerUserId,
        q.CreationDate,
        COUNT(a.Id) AS AnswerCount,
        ROW_NUMBER() OVER (ORDER BY q.ViewCount DESC, q.Score DESC) AS rn
    FROM Posts q
    LEFT JOIN Posts a ON a.ParentId = q.Id AND a.PostTypeId = 2
    WHERE q.PostTypeId = 1
      AND q.CreationDate >= NOW() - INTERVAL '90 days'
      AND q.ViewCount > 1000
    GROUP BY q.Id, q.Title, q.Score, q.ViewCount, q.OwnerUserId, q.CreationDate
),
UserBadges AS (
    SELECT 
        b.UserId,
        COUNT(*) FILTER (WHERE b.Class = 1) AS GoldBadges,
        COUNT(*) FILTER (WHERE b.Class = 2) AS SilverBadges,
        COUNT(*) FILTER (WHERE b.Class = 3) AS BronzeBadges,
        MAX(b.Date) AS LastBadgeDate
    FROM Badges b
    GROUP BY b.UserId
),
QuestionVotes AS (
    SELECT 
        v.PostId,
        SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) AS Upvotes,
        SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) AS Downvotes,
        COUNT(*) AS TotalVotes
    FROM Votes v
    INNER JOIN Posts p ON p.Id = v.PostId
    WHERE p.PostTypeId = 1
      AND v.CreationDate >= NOW() - INTERVAL '90 days'
    GROUP BY v.PostId
)
SELECT 
    rau.UserId,
    rau.DisplayName,
    rau.Reputation,
    rau.TotalPosts,
    rau.TotalQuestions,
    rau.TotalAnswers,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.LastBadgeDate,
    hq.QuestionId,
    hq.Title AS HotQuestionTitle,
    hq.Score AS HotQuestionScore,
    hq.ViewCount AS HotQuestionViews,
    hq.AnswerCount AS HotQuestionAnswers,
    qv.Upvotes AS HotQuestionUpvotes,
    qv.Downvotes AS HotQuestionDownvotes,
    qv.TotalVotes AS HotQuestionTotalVotes
FROM RecentActiveUsers rau
LEFT JOIN UserBadges ub ON rau.UserId = ub.UserId
LEFT JOIN HotQuestions hq ON rau.UserId = hq.OwnerUserId AND hq.rn <= 3
LEFT JOIN QuestionVotes qv ON hq.QuestionId = qv.PostId
ORDER BY rau.TotalPosts DESC, hq.ViewCount DESC NULLS LAST, rau.UserId
LIMIT 100;