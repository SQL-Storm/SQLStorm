-- {"query": "20094.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-pro", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1666} 

WITH UserMetrics AS (
    -- Step 1: Identify highly reputable users with significant badge counts.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        SUM(CASE WHEN b.Class = 2 THEN 1 ELSE 0 END) AS SilverBadges,
        SUM(CASE WHEN b.Class = 3 THEN 1 ELSE 0 END) AS BronzeBadges,
        (
            SELECT MAX(ph.CreationDate)
            FROM PostHistory ph
            WHERE ph.UserId = u.Id AND ph.PostHistoryTypeId IN (2, 5, 8) -- Initial Body, Edit Body, Rollback Body
        ) AS LastBodyEditDate
    FROM
        Users u
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    WHERE
        u.Reputation > 50000 AND u.Views > 1000 AND u.UpVotes > u.DownVotes * 5
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate
    HAVING
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) >= 10
),
UserPostDetails AS (
    -- Step 2: For these users, gather their posts and calculate time-based and rank-based metrics.
    SELECT
        p.Id AS PostId,
        p.OwnerUserId,
        p.PostTypeId,
        p.CreationDate,
        p.Score,
        p.Title,
        p.Tags,
        p.ParentId,
        p.AcceptedAnswerId,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        COALESCE(p.ClosedDate, p.CommunityOwnedDate) AS FinalStatusDate,
        LAG(p.CreationDate, 1, p.CreationDate) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostDate,
        RANK() OVER (PARTITION BY p.OwnerUserId, p.PostTypeId ORDER BY p.Score DESC) AS RankByScore,
        NTILE(100) OVER (PARTITION BY p.OwnerUserId ORDER BY p.ViewCount) AS ViewCountPercentile,
        (p.Score::decimal / NULLIF(p.ViewCount, 0)) * 100 AS ScoreToViewRatio
    FROM
        Posts p
    WHERE
        p.OwnerUserId IN (SELECT UserId FROM UserMetrics) AND p.PostTypeId IN (1, 2) -- Questions and Answers
),
CombinedAnalysis AS (
    -- Step 3: Combine user and post data, analyze questions.
    SELECT
        um.UserId,
        um.DisplayName,
        um.Reputation,
        um.GoldBadges,
        upd.PostId AS QuestionId,
        NULL AS AnswerId,
        upd.Title AS PostTitle,
        'Question' AS PostType,
        upd.CreationDate,
        upd.Score,
        upd.ScoreToViewRatio,
        upd.RankByScore,
        EXTRACT(EPOCH FROM (upd.CreationDate - upd.PreviousPostDate)) / 3600 AS HoursSinceLastPost,
        (SELECT aa.Score FROM Posts aa WHERE aa.Id = upd.AcceptedAnswerId) AS AcceptedAnswerScore,
        -- Correlated subquery to find number of linked posts
        (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = upd.PostId AND pl.LinkTypeId = 1) AS LinkedPostCount,
        string_to_array(substring(upd.Tags, 2, length(upd.Tags)-2), '><') AS TagsArray
    FROM
        UserMetrics um
    JOIN
        UserPostDetails upd ON um.UserId = upd.OwnerUserId
    WHERE
        upd.PostTypeId = 1 AND upd.RankByScore <= 5 AND upd.FavoriteCount > 10

    UNION ALL

    -- Step 4: Analyze answers.
    SELECT
        um.UserId,
        um.DisplayName,
        um.Reputation,
        um.GoldBadges,
        q.Id AS QuestionId,
        upd.PostId AS AnswerId,
        CONCAT('Re: ', q.Title) AS PostTitle,
        'Answer' AS PostType,
        upd.CreationDate,
        upd.Score,
        upd.ScoreToViewRatio,
        upd.RankByScore,
        EXTRACT(EPOCH FROM (upd.CreationDate - upd.PreviousPostDate)) / 3600 AS HoursSinceLastPost,
        NULL AS AcceptedAnswerScore,
        (SELECT COUNT(*) FROM Votes v WHERE v.PostId = upd.PostId AND v.VoteTypeId = 2) AS UpVotesOnAnswer,
        NULL AS TagsArray
    FROM
        UserMetrics um
    JOIN
        UserPostDetails upd ON um.UserId = upd.OwnerUserId
    LEFT JOIN
        Posts q ON upd.ParentId = q.Id
    WHERE
        upd.PostTypeId = 2 AND upd.Score > (SELECT AVG(p_inner.Score) FROM Posts p_inner WHERE p_inner.OwnerUserId = um.UserId AND p_inner.PostTypeId = 2)
)
-- Step 5: Final aggregation and filtering.
SELECT
    ca.UserId,
    ca.DisplayName,
    ca.Reputation,
    ca.PostType,
    ca.PostId,
    LEFT(ca.PostTitle, 80) AS TruncatedTitle,
    ca.Score,
    ca.RankByScore,
    ca.HoursSinceLastPost,
    CASE
        WHEN ca.PostType = 'Question' AND ca.Score > 100 AND array_length(ca.TagsArray, 1) > 3 THEN 'High-Value Question'
        WHEN ca.PostType = 'Answer' AND ca.Score > 50 THEN 'High-Value Answer'
        ELSE 'Standard Contribution'
    END AS ContributionQuality,
    (
        -- Check if user commented on their own accepted answer's question post.
        SELECT EXISTS (
            SELECT 1
            FROM Comments c
            JOIN Posts p_ans ON c.PostId = p_ans.ParentId
            WHERE c.UserId = ca.UserId
              AND p_ans.Id = (SELECT AcceptedAnswerId FROM Posts WHERE Id = ca.QuestionId)
        )
    ) AS CommentedOnAcceptedAnswerThread
FROM
    CombinedAnalysis ca
WHERE
    ca.Score > 0
    AND (
        ca.PostType = 'Question'
        AND ca.TagsArray @> ARRAY['sql']
        AND (ca.PostTitle ILIKE '%performance%' OR ca.PostTitle ILIKE '%optim%')
    )
    OR
    (
        ca.PostType = 'Answer'
        AND ca.HoursSinceLastPost < 24
    )
ORDER BY
    ca.Reputation DESC,
    ca.UserId,
    ca.CreationDate DESC
LIMIT 200;
