-- {"query": "1475.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 2564} 

WITH UserEngagementSummary AS (
    -- CTE 1: Aggregates comprehensive user activity and classifies users by reputation tiers.
    -- Includes counts of posts, comments, badges, and votes received, using LEFT JOINs to retain all users.
    SELECT
        u.Id AS UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.Views AS TotalProfileViews,
        COALESCE(u.UpVotes, 0) AS TotalUpVotesGiven,
        COALESCE(u.DownVotes, 0) AS TotalDownVotesGiven,
        COUNT(DISTINCT p.Id) AS TotalPostsOwned,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestionsOwned,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswersOwned,
        COUNT(DISTINCT c.Id) AS TotalCommentsMade,
        COUNT(DISTINCT b.Id) AS TotalBadgesEarned,
        SUM(COALESCE(p.Score, 0)) AS TotalPostScoreReceived,
        (CASE
            WHEN u.Reputation >= 100000 THEN 'Legend'
            WHEN u.Reputation >= 25000 THEN 'Veteran'
            WHEN u.Reputation >= 5000 THEN 'Expert'
            WHEN u.Reputation >= 1000 THEN 'Journeyman'
            ELSE 'Novice'
        END) AS ReputationTier,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 2 THEN v.PostId END) AS PostsUpvoted,
        COUNT(DISTINCT CASE WHEN v.VoteTypeId = 3 THEN v.PostId END) AS PostsDownvoted
    FROM
        Users u
    LEFT JOIN
        Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN
        Comments c ON u.Id = c.UserId
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    LEFT JOIN
        Votes v ON u.Id = v.UserId AND v.VoteTypeId IN (2, 3) -- Votes *given* by the user
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.Views, u.UpVotes, u.DownVotes
),
PostMetricsEnhanced AS (
    -- CTE 2: Augments post information with calculated engagement scores, topic categorization, and parent post details.
    -- Utilizes string functions for tag analysis and a subquery to check for popular parent questions.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        COALESCE(p.OwnerDisplayName, u_owner.DisplayName, 'Community') AS EffectivePostOwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.LastEditDate AS PostLastEditDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.Title,
        p.Tags,
        p.AcceptedAnswerId,
        p.ParentId,
        COALESCE(p.Score, 0) * 1.5 + (COALESCE(p.ViewCount, 0) * 0.02) + (COALESCE(p.CommentCount, 0) * 0.8) + (COALESCE(p.FavoriteCount, 0) * 3) AS WeightedEngagementScore,
        (p.Score::DECIMAL / NULLIF(p.ViewCount, 0)) AS ScorePerViewRatio,
        CASE
            WHEN p.Tags LIKE '%<sql>%' OR p.Tags LIKE '%<database>%' OR p.Tags LIKE '%<performance>%' OR p.Tags LIKE '%<tuning>%' THEN TRUE
            ELSE FALSE
        END AS IsTechnicalTopic,
        EXISTS (
            SELECT 1
            FROM Posts parent_p
            WHERE parent_p.Id = p.ParentId
            AND parent_p.Score > 500
            AND parent_p.ViewCount > 10000
            AND parent_p.PostTypeId = 1
        ) AS IsAnswerToHighlyViewedQuestion,
        EXTRACT(EPOCH FROM (NOW() - p.CreationDate)) / (60 * 60 * 24) AS DaysOld, -- Post age in days
        COALESCE(p.LastEditorUserId, p.OwnerUserId) AS CurrentEditorUserId,
        (SELECT COUNT(DISTINCT co.Id) FROM Comments co WHERE co.PostId = p.Id AND co.UserId IS NOT NULL AND co.CreationDate >= (NOW() - INTERVAL '6 month')) AS RecentCommentersCount
    FROM
        Posts p
    JOIN
        PostTypes pt ON p.PostTypeId = pt.Id
    LEFT JOIN
        Users u_owner ON p.OwnerUserId = u_owner.Id
    WHERE
        p.CreationDate >= (NOW() - INTERVAL '5 year') -- Filter for relatively recent posts
),
SelfEditFrequency AS (
    -- CTE 3: Calculates how often a post owner edits their own posts.
    -- Filters for specific PostHistoryTypes indicating content edits.
    SELECT
        ph.PostId,
        ph.UserId AS EditorUserId,
        COUNT(ph.Id) AS TotalSelfEdits,
        MAX(ph.CreationDate) AS LastSelfEditDate,
        MIN(ph.CreationDate) AS FirstSelfEditDate
    FROM
        PostHistory ph
    JOIN
        Posts p ON ph.PostId = p.Id
    WHERE
        ph.UserId = p.OwnerUserId -- Only count edits by the post owner
        AND ph.PostHistoryTypeId IN (4, 5, 6, 8, 9) -- Edit Title, Edit Body, Edit Tags, Rollback Body/Tags
    GROUP BY
        ph.PostId, ph.UserId
    HAVING
        COUNT(ph.Id) >= 1 -- Consider posts with at least one self-edit
)
SELECT
    ues.UserId,
    ues.DisplayName,
    ues.Reputation,
    ues.ReputationTier,
    pme.PostId,
    pme.PostTypeName,
    pme.EffectivePostOwnerDisplayName,
    pme.Title,
    pme.Tags,
    pme.Score AS PostScore,
    pme.ViewCount AS PostViewCount,
    pme.WeightedEngagementScore,
    pme.ScorePerViewRatio,
    pme.IsTechnicalTopic,
    pme.IsAnswerToHighlyViewedQuestion,
    COALESCE(sef.TotalSelfEdits, 0) AS NumberOfSelfEdits,
    sef.LastSelfEditDate,
    LAG(pme.Score, 1, 0) OVER (PARTITION BY ues.UserId ORDER BY pme.PostCreationDate) AS ScoreOfPreviousPost,
    AVG(pme.Score) OVER (PARTITION BY ues.ReputationTier) AS AverageScoreInUserTier,
    NTILE(10) OVER (ORDER BY pme.WeightedEngagementScore DESC) AS GlobalEngagementDecile,
    (SELECT AVG(sub_p.Score)
     FROM Posts sub_p
     WHERE sub_p.OwnerUserId = ues.UserId
       AND sub_p.PostTypeId = 1
       AND sub_p.CreationDate >= (NOW() - INTERVAL '3 year')
       AND sub_p.AcceptedAnswerId IS NOT NULL -- Only accepted questions
    ) AS UserAvgAcceptedQuestionScoreLast3Y,
    COALESCE(pme.PostLastEditDate, ues.LastAccessDate, pme.PostCreationDate) AS EffectiveLastContentActivity,
    REPLACE(
        TRIM(
            UPPER(
                SUBSTRING(
                    pme.Tags,
                    POSITION('<' IN pme.Tags) + 1,
                    POSITION('>' IN pme.Tags) - POSITION('<' IN pme.Tags) - 1
                )
            )
        ),
        'SQL',
        'StructuredQueryLanguage'
    ) AS PrimaryTagNormalized,
    (CASE
        WHEN pme.PostTypeId = 1 AND pme.AcceptedAnswerId IS NOT NULL THEN 'Question_AcceptedAnswer'
        WHEN pme.PostTypeId = 2 AND pme.ParentId IS NOT NULL AND pme.PostId = (SELECT AcceptedAnswerId FROM Posts WHERE Id = pme.ParentId) THEN 'Answer_Accepted'
        WHEN pme.PostTypeId = 1 AND pme.AnswerCount = 0 THEN 'Question_Unanswered'
        WHEN pme.PostTypeId = 1 AND pme.ClosedDate IS NOT NULL THEN 'Question_Closed'
        WHEN pme.PostTypeId = 2 AND pme.Score >= 50 THEN 'Answer_HighScore'
        ELSE 'Other_RelevantPost'
    END) AS DetailedPostStatusCategory,
    pme.RecentCommentersCount,
    (EXTRACT(YEAR FROM NOW()) - EXTRACT(YEAR FROM ues.UserCreationDate)) AS UserAccountAgeYears,
    (EXTRACT(YEAR FROM NOW()) - EXTRACT(YEAR FROM pme.PostCreationDate)) AS PostAgeYears
FROM
    UserEngagementSummary ues
LEFT JOIN
    PostMetricsEnhanced pme ON ues.UserId = pme.OwnerUserId
LEFT JOIN
    SelfEditFrequency sef ON pme.PostId = sef.PostId AND ues.UserId = sef.EditorUserId
WHERE
    ues.TotalPostsOwned > 0
    AND ues.Reputation >= 2000 -- Filter for more established users
    AND pme.Score >= 20
    AND pme.ViewCount >= 1000
    AND pme.IsTechnicalTopic = TRUE
    AND (pme.Tags LIKE '%<sql>%' OR pme.Tags LIKE '%<database>%') -- Specific technical tags
    AND NOT EXISTS (
        SELECT 1
        FROM PostHistory ph_close
        WHERE ph_close.PostId = pme.PostId
          AND ph_close.PostHistoryTypeId = 10 -- Post Closed type
          AND ph_close.CreationDate >= (NOW() - INTERVAL '2 year') -- Not recently closed
    )
    AND ues.DisplayName IS NOT NULL AND LENGTH(TRIM(ues.DisplayName)) > 0 -- Ensure display name is present and not empty
    AND pme.Title IS NOT NULL AND LENGTH(TRIM(pme.Title)) > 0 -- Ensure title is present and not empty
    AND pme.ScorePerViewRatio IS NOT NULL AND pme.ScorePerViewRatio > 0.001 -- Filter out very low engagement posts
    AND COALESCE(sef.TotalSelfEdits, 0) >= 0 -- Include posts even without self-edits, but leverage the join if edits exist
ORDER BY
    ues.Reputation DESC,
    pme.WeightedEngagementScore DESC,
    COALESCE(sef.TotalSelfEdits, 0) DESC,
    pme.PostCreationDate ASC
LIMIT 500;
