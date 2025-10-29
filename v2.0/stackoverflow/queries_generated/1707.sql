-- {"query": "1707.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3182} 

WITH UserEngagement AS (
    -- Summarizes core user activity metrics, incorporating badges, posts, comments, and bounties.
    SELECT
        u.Id AS UserId,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.DisplayName,
        u.Location,
        u.WebsiteUrl,
        u.Views AS UserProfileViews,
        u.UpVotes AS UserUpVotes,
        u.DownVotes AS UserDownVotes,
        COUNT(DISTINCT p.Id) AS TotalPosts,
        SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END) AS TotalQuestions,
        SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END) AS TotalAnswers,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        MAX(b.Date) AS LastBadgeDate,
        AVG(COALESCE(p.Score, 0)) AS AvgPostScore,
        MAX(p.LastActivityDate) AS LastPostActivityDate,
        (SELECT COUNT(DISTINCT c.Id) FROM Comments c WHERE c.UserId = u.Id) AS TotalCommentsMade, -- Correlated subquery for total comments made by user
        (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.UserId = u.Id AND v.VoteTypeId = 8) AS TotalBountyGiven, -- Correlated subquery for bounties given
        (SELECT SUM(v.BountyAmount) FROM Votes v WHERE v.PostId IN (SELECT p_inner.Id FROM Posts p_inner WHERE p_inner.OwnerUserId = u.Id) AND v.VoteTypeId = 9) AS TotalBountyReceived -- Correlated subquery for bounties received
    FROM Users u
    LEFT JOIN Posts p ON u.Id = p.OwnerUserId
    LEFT JOIN Badges b ON u.Id = b.UserId
    GROUP BY u.Id, u.Reputation, u.CreationDate, u.DisplayName, u.Location, u.WebsiteUrl, u.Views, u.UpVotes, u.DownVotes
),
PostDetailsExtended AS (
    -- Extracts detailed post information, including parsed tags, age, status, and preliminary edit counts.
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        pt.Name AS PostTypeName,
        p.OwnerUserId,
        p.CreationDate AS PostCreationDate,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.AcceptedAnswerId,
        p.ParentId,
        p.Title,
        p.Tags,
        p.Body, -- Include body for string manipulation
        p.LastEditDate,
        p.LastActivityDate,
        p.ClosedDate,
        p.CommunityOwnedDate,
        COALESCE(p.AcceptedAnswerId, -1) AS ValidAcceptedAnswerId, -- Handles NULL for AcceptedAnswerId
        EXTRACT(EPOCH FROM (NOW() - p.CreationDate)) / 86400 AS PostAgeDays, -- Calculates post age in days
        ARRAY(
            SELECT UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><'))
            WHERE p.Tags IS NOT NULL AND LENGTH(p.Tags) > 2
        ) AS TagArray, -- Converts tags string into an array
        CASE
            WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
            WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Wiki'
            ELSE 'Open'
        END AS PostStatus,
        LENGTH(p.Body) AS BodyLength,
        (SELECT COUNT(DISTINCT ph.Id) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6,8,9,24)) AS EditCount, -- Counts various types of post edits
        (SELECT MAX(ph.CreationDate) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (4,5,6,8,9,24)) AS LastEditHistoryDate -- Gets the date of the last relevant edit
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
),
PostLinkAnalysis AS (
    -- Summarizes linked and duplicate posts for each PostId.
    SELECT
        pl.PostId,
        STRING_AGG(CASE WHEN pl.LinkTypeId = 1 THEN 'Linked' ELSE 'Duplicate' END || ':' || pl.RelatedPostId::VARCHAR, '; ') AS RelatedPostsSummary, -- Aggregates linked/duplicate post information
        COUNT(CASE WHEN pl.LinkTypeId = 1 THEN 1 END) AS LinkedPostCount,
        COUNT(CASE WHEN pl.LinkTypeId = 3 THEN 1 END) AS DuplicatePostCount,
        MAX(pl.CreationDate) AS LastLinkDate
    FROM PostLinks pl
    GROUP BY pl.PostId
),
TopTagsPerPost AS (
    -- Identifies the primary tag for each question post, assuming the first tag in the array is most significant.
    SELECT
        pd.PostId,
        (SELECT UNNEST(pd.TagArray) LIMIT 1) AS PrimaryTag -- Extracts the first tag from the array
    FROM PostDetailsExtended pd
    WHERE pd.PostTypeId = 1 AND array_length(pd.TagArray, 1) > 0
),
ModeratorActionSummary AS (
    -- Summarizes moderator actions, including close reasons, for posts.
    SELECT
        ph.PostId,
        STRING_AGG(DISTINCT pht.Name, ', ') AS ModeratorActionTypes,
        COUNT(DISTINCT ph.Id) AS TotalModeratorActions,
        MAX(ph.CreationDate) AS LastModeratorActionDate,
        COUNT(CASE WHEN ph.PostHistoryTypeId = 10 THEN 1 ELSE NULL END) AS CloseVotesHistoryCount,
        STRING_AGG(DISTINCT crt.Name, ';') FILTER (WHERE ph.PostHistoryTypeId = 10 AND ph.Comment IS NOT NULL) AS CloseReasonDetails -- Aggregates close reasons
    FROM PostHistory ph
    JOIN PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    LEFT JOIN CloseReasonTypes crt ON ph.PostHistoryTypeId = 10 AND ph.Comment = crt.Id::VARCHAR -- Joins to get close reason name
    WHERE ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) -- Filters for specific moderator actions
    GROUP BY ph.PostId
)
SELECT
    ue.UserId,
    ue.DisplayName AS UserDisplayName,
    ue.Reputation,
    ue.UserCreationDate,
    ue.Location AS UserLocation,
    COALESCE(ue.WebsiteUrl, 'N/A') AS UserWebsite, -- Handles NULL WebsiteUrl
    ue.UserProfileViews,
    ue.TotalPosts,
    ue.TotalQuestions,
    ue.TotalAnswers,
    ue.TotalBadges,
    ue.LastBadgeDate,
    ue.AvgPostScore,
    ue.TotalCommentsMade,
    ue.TotalBountyGiven,
    ue.TotalBountyReceived,

    -- Top Question Details for the user (using LATERAL join for performance and clarity)
    q.PostId AS TopQuestionId,
    q.Title AS TopQuestionTitle,
    q.Score AS TopQuestionScore,
    q.ViewCount AS TopQuestionViewCount,
    q.AnswerCount AS TopQuestionAnswerCount,
    q.FavoriteCount AS TopQuestionFavoriteCount,
    q.PostAgeDays AS TopQuestionAgeDays,
    q.PostStatus AS TopQuestionStatus,
    q.EditCount AS TopQuestionEditCount,
    q.BodyLength AS TopQuestionBodyLength,
    COALESCE(tpp.PrimaryTag, 'untagged') AS TopQuestionPrimaryTag, -- Handles NULL for primary tag
    pla_q.RelatedPostsSummary AS TopQuestionLinkedInfo,
    mas_q.ModeratorActionTypes AS TopQuestionModActions,
    mas_q.CloseReasonDetails AS TopQuestionCloseReasons,

    -- Top Answer Details for the user (using LATERAL join)
    a.PostId AS TopAnswerId,
    a.Title AS TopAnswerQuestionTitle, -- Title of the parent question if applicable, fetched via correlated subquery
    a.Score AS TopAnswerScore,
    a.PostAgeDays AS TopAnswerAgeDays,
    a.PostStatus AS TopAnswerStatus,
    a.EditCount AS TopAnswerEditCount,
    (
        SELECT
            COUNT(c_inner.Id)
        FROM Comments c_inner
        WHERE c_inner.PostId = a.Id
          AND c_inner.CreationDate > a.CreationDate -- Correlated subquery for positive comments made after answer creation
          AND c_inner.Score > 0
    ) AS TopAnswerPositiveCommentCount,
    pla_a.RelatedPostsSummary AS TopAnswerLinkedInfo,
    mas_a.ModeratorActionTypes AS TopAnswerModActions,

    -- Overall user activity metrics derived from window functions
    ROW_NUMBER() OVER (ORDER BY ue.Reputation DESC, ue.TotalQuestions DESC, ue.TotalAnswers DESC) AS GlobalUserRank, -- Ranks users globally
    AVG(ue.TotalQuestions) OVER (PARTITION BY ue.Location) AS AvgQuestionsInLocation, -- Average questions per user's location
    MAX(ue.LastPostActivityDate) OVER (PARTITION BY DATE_TRUNC('month', ue.UserCreationDate)) AS LastActivityForCreationMonth, -- Last activity for users created in the same month
    ue.UserUpVotes - ue.UserDownVotes AS NetUserVotes, -- Calculates net votes for the user
    EXTRACT(YEAR FROM NOW()) - EXTRACT(YEAR FROM ue.UserCreationDate) AS YearsOnPlatform, -- Calculates years since registration

    -- Complex expression for user influence score
    (
        (ue.Reputation * 0.5)
        + (ue.TotalPosts * 0.1)
        + (COALESCE(q.Score, 0) * 0.2)
        + (COALESCE(a.Score, 0) * 0.2)
        + (COALESCE(q.ViewCount, 0) * 0.005)
        + (ue.TotalBadges * 10)
        + (ue.TotalCommentsMade * 0.05)
        - (ue.UserDownVotes * 0.1) -- Penalty for user's downvotes
    ) AS UserInfluenceScore,

    -- String manipulation examples
    UPPER(SUBSTRING(ue.DisplayName, 1, 1)) AS FirstLetterOfDisplayName,
    REPLACE(REPLACE(REPLACE(LOWER(SUBSTRING(COALESCE(q.Body, ''), 1, 500)), 'sql', '[SQL_TERM]'), 'database', '[DB_TERM]'), 'query', '[QUERY_TERM]') AS SanitizedQuestionBodySnippet, -- Sanitizes/highlights keywords in body
    (SELECT COUNT(*) FROM Posts p_inner WHERE p_inner.OwnerUserId = ue.UserId AND p_inner.PostTypeId = 1 AND p_inner.Title LIKE '%performance%') AS PerformanceQuestionCount, -- Counts user's questions about 'performance'

    -- Date difference for last post edit vs. creation
    EXTRACT(EPOCH FROM (q.LastEditHistoryDate - q.PostCreationDate)) / 3600 AS HoursSinceFirstEditForTopQuestion, -- Hours between first post creation and last edit
    EXTRACT(EPOCH FROM (a.LastEditHistoryDate - a.PostCreationDate)) / 3600 AS HoursSinceFirstEditForTopAnswer

FROM
    UserEngagement ue
LEFT JOIN LATERAL (
    -- Lateral join to efficiently find the highest scoring question for each user.
    SELECT pd.*
    FROM PostDetailsExtended pd
    WHERE pd.OwnerUserId = ue.UserId
      AND pd.PostTypeId = 1
    ORDER BY pd.Score DESC, pd.ViewCount DESC, pd.CreationDate DESC
    LIMIT 1
) q ON TRUE
LEFT JOIN LATERAL (
    -- Lateral join to efficiently find the highest scoring answer for each user.
    SELECT pd.*, (SELECT p_q.Title FROM Posts p_q WHERE p_q.Id = pd.ParentId) AS Title -- Fetches parent question title for context
    FROM PostDetailsExtended pd
    WHERE pd.OwnerUserId = ue.UserId
      AND pd.PostTypeId = 2
    ORDER BY pd.Score DESC, pd.CreationDate DESC
    LIMIT 1
) a ON TRUE
LEFT JOIN TopTagsPerPost tpp ON q.PostId = tpp.PostId
LEFT JOIN PostLinkAnalysis pla_q ON q.PostId = pla_q.PostId
LEFT JOIN PostLinkAnalysis pla_a ON a.PostId = pla_a.PostId
LEFT JOIN ModeratorActionSummary mas_q ON q.PostId = mas_q.PostId
LEFT JOIN ModeratorActionSummary mas_a ON a.PostId = mas_a.PostId
WHERE
    ue.Reputation > 1000 -- Filters for users with substantial reputation
    AND ue.TotalPosts > 5 -- Filters for users with a minimum number of posts
    AND ue.UserCreationDate < NOW() - INTERVAL '1 year' -- Only considers users older than 1 year
    AND (
        q.PostId IS NOT NULL -- Ensures the user has at least one question
        OR a.PostId IS NOT NULL -- Or at least one answer
    )
    AND (
        LOWER(ue.Location) LIKE '%london%'
        OR LOWER(ue.Location) LIKE '%new york%'
        OR ue.Location IS NULL -- Example of complex NULL logic in WHERE clause for location
    )
ORDER BY
    UserInfluenceScore DESC, GlobalUserRank ASC
LIMIT 1000;
