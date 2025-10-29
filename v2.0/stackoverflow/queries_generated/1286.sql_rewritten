-- {"query": "1286.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 3347} 
WITH UserMetrics AS (
    SELECT
        u.Id AS UserId,
        u.DisplayName AS UserName,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        u.LastAccessDate,
        u.UpVotes,
        u.DownVotes,
        u.Views AS UserProfileViews,
        COALESCE(u.Location, 'Unknown Location') AS UserLocation,
        CASE
            WHEN u.Reputation >= 100000 THEN 'Stack Overflow Legend'
            WHEN u.Reputation >= 50000 THEN 'Distinguished Expert'
            WHEN u.Reputation >= 10000 THEN 'Seasoned Contributor'
            WHEN u.Reputation >= 1000 THEN 'Active Participant'
            ELSE 'Newbie'
        END AS ReputationTier,
        COUNT(DISTINCT b.Id) AS TotalBadges,
        SUM(CASE WHEN b.Class = 1 THEN 1 ELSE 0 END) AS GoldBadges,
        MAX(b.Date) AS LatestBadgeDate,
        DENSE_RANK() OVER (ORDER BY u.Reputation DESC, u.CreationDate ASC) AS GlobalReputationRank,
        ROW_NUMBER() OVER (PARTITION BY COALESCE(u.Location, 'Unknown Location') ORDER BY u.Reputation DESC) AS LocationReputationRank
    FROM
        Users u
    LEFT JOIN
        Badges b ON u.Id = b.UserId
    WHERE
        u.LastAccessDate >= '2022-01-01' -- Focus on recently active users
        AND u.DisplayName IS NOT NULL
        AND u.AccountId IS NOT NULL
    GROUP BY
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate, u.UpVotes, u.DownVotes, u.Views, u.Location
    HAVING
        COUNT(b.Id) > 0 -- Users with at least one badge
),
PostTagParser AS (
    SELECT
        p_tag.Id AS PostId,
        UNNEST(string_to_array(SUBSTRING(p_tag.Tags, 2, LENGTH(p_tag.Tags) - 2), '><')) AS TagName
    FROM Posts p_tag
    WHERE p_tag.Tags IS NOT NULL AND LENGTH(p_tag.Tags) > 2
),
PostEngagementSummary AS (
    -- Questions with high engagement
    SELECT
        q.Id AS PostId,
        q.OwnerUserId,
        q.Title AS PostTitle,
        q.CreationDate AS PostCreationDate,
        q.Score AS PostScore,
        q.ViewCount AS PostViewCount,
        q.CommentCount AS PostCommentCount,
        q.FavoriteCount AS PostFavoriteCount,
        q.PostTypeId,
        'Question' AS PostTypeCategory,
        NULL AS ParentQuestionId, -- Not applicable for questions
        STRING_AGG(DISTINCT ptp.TagName, ', ') AS AssociatedTags,
        -- Correlated subquery: Average score of answers for this specific question
        (SELECT AVG(a_sub.Score) FROM Posts a_sub WHERE a_sub.ParentId = q.Id AND a_sub.PostTypeId = 2 AND a_sub.Score > 0) AS AvgPositiveAnswerScoreForThisPost,
        NULLIF(q.AcceptedAnswerId, -1) AS AcceptedAnswerRefId,
        ROW_NUMBER() OVER (PARTITION BY q.OwnerUserId ORDER BY q.Score DESC, q.ViewCount DESC, q.CreationDate DESC) AS UserPostRank
    FROM
        Posts q
    LEFT JOIN
        PostTagParser ptp ON q.Id = ptp.PostId
    WHERE
        q.PostTypeId = 1 -- Questions
        AND q.Score >= 15
        AND q.ViewCount >= 2000
        AND q.AnswerCount > 0
    GROUP BY
        q.Id, q.OwnerUserId, q.Title, q.CreationDate, q.Score, q.ViewCount, q.CommentCount, q.FavoriteCount, q.PostTypeId, q.AcceptedAnswerId

    UNION ALL

    -- High-scoring answers from active users
    SELECT
        a.Id AS PostId,
        a.OwnerUserId,
        SUBSTRING(a.Body, 1, 150) || '...' AS PostTitle, -- Snippet of the answer body
        a.CreationDate AS PostCreationDate,
        a.Score AS PostScore,
        NULL AS PostViewCount, -- Answers typically don't have direct view counts
        a.CommentCount AS PostCommentCount,
        NULL AS PostFavoriteCount, -- Answers typically don't have favorite counts
        a.PostTypeId,
        'Answer' AS PostTypeCategory,
        a.ParentId AS ParentQuestionId, -- The question this answer belongs to
        STRING_AGG(DISTINCT ptp.TagName, ', ') AS AssociatedTags, -- Inherit tags from parent question
        NULL AS AvgPositiveAnswerScoreForThisPost, -- Not applicable for answers
        NULLIF(a.Id, -1) AS AcceptedAnswerRefId, -- Is this answer itself an accepted answer?
        ROW_NUMBER() OVER (PARTITION BY a.OwnerUserId ORDER BY a.Score DESC, a.CreationDate DESC) AS UserPostRank
    FROM
        Posts a
    LEFT JOIN
        PostTagParser ptp ON a.ParentId = ptp.PostId -- Link answers to their parent question's tags
    WHERE
        a.PostTypeId = 2 -- Answers
        AND a.Score >= 10
        AND a.ParentId IS NOT NULL -- Must belong to a question
    GROUP BY
        a.Id, a.OwnerUserId, a.Body, a.CreationDate, a.Score, a.CommentCount, a.PostTypeId, a.ParentId
),
PostHistoryTimeline AS (
    SELECT
        ph.PostId,
        ph.UserId AS HistoryActorId,
        ph.PostHistoryTypeId,
        ph.CreationDate AS HistoryDate,
        pht.Name AS HistoryTypeName,
        COALESCE(ph.Comment, 'N/A') AS HistoryComment,
        LEAD(ph.CreationDate, 1) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS NextHistoryEventDate,
        LAG(ph.CreationDate, 1) OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate) AS PreviousHistoryEventDate,
        COUNT(ph.Id) OVER (PARTITION BY ph.PostId) AS TotalPostHistoryEvents
    FROM
        PostHistory ph
    JOIN
        PostHistoryTypes pht ON ph.PostHistoryTypeId = pht.Id
    WHERE
        ph.CreationDate >= '2020-01-01'
        AND ph.PostHistoryTypeId IN (5, 6, 10, 11, 12, 13) -- Body Edit, Tags Edit, Closed, Reopened, Deleted, Undeleted
),
PostLinkAnalysis AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostsCount,
        COUNT(DISTINCT CASE WHEN pl.LinkTypeId = 3 THEN pl.RelatedPostId END) AS DuplicatePostsCount,
        STRING_AGG(DISTINCT lt.Name, ', ') FILTER (WHERE lt.Name IS NOT NULL) AS LinkTypeNames
    FROM
        PostLinks pl
    JOIN
        LinkTypes lt ON pl.LinkTypeId = lt.Id
    GROUP BY
        pl.PostId
),
UserCommentActivity AS (
    SELECT
        c.UserId,
        COUNT(c.Id) AS TotalUserComments,
        SUM(c.Score) AS TotalUserCommentScore,
        AVG(c.Score) AS AvgUserCommentScore,
        MAX(c.CreationDate) AS LastUserCommentDate,
        NTILE(5) OVER (ORDER BY SUM(c.Score) DESC) AS CommentScoreQuintile
    FROM
        Comments c
    WHERE
        c.UserId IS NOT NULL
        AND LENGTH(c.Text) > 20 -- Meaningful comments
        AND c.Text LIKE '%bug%' OR c.Text LIKE '%feature%' -- Comments discussing issues or features
    GROUP BY
        c.UserId
    HAVING
        COUNT(c.Id) >= 5 -- Users with substantial comment engagement
)
-- Final Query: Aggregating diverse metrics for influential content creators
SELECT
    um.UserId,
    um.UserName,
    um.Reputation,
    um.ReputationTier,
    um.GlobalReputationRank,
    um.UserLocation,
    um.TotalBadges,
    um.GoldBadges,
    pes.PostId,
    pes.PostTitle,
    pes.PostTypeCategory,
    pes.PostScore,
    COALESCE(pes.PostViewCount, 0) AS EffectivePostViewCount, -- Handle NULL for answers
    pes.PostCommentCount,
    COALESCE(pes.PostFavoriteCount, 0) AS EffectivePostFavoriteCount,
    pes.AssociatedTags,
    pes.AvgPositiveAnswerScoreForThisPost,
    pes.AcceptedAnswerRefId,
    pla.LinkedPostsCount,
    pla.DuplicatePostsCount,
    pla.LinkTypeNames,
    ucom.TotalUserComments,
    ucom.TotalUserCommentScore,
    ucom.AvgUserCommentScore,
    ucom.CommentScoreQuintile,
    MAX(CASE WHEN pht.HistoryTypeName = 'Post Closed' THEN pht.HistoryDate END) AS LastClosedDate,
    MAX(CASE WHEN pht.HistoryTypeName = 'Post Reopened' THEN pht.HistoryDate END) AS LastReopenedDate,
    SUM(CASE WHEN pht.PostHistoryTypeId IN (5, 6) THEN 1 ELSE 0 END) AS TotalMajorEditsByAnyone, -- Edits from history
    MIN(EXTRACT(EPOCH FROM (pht.NextHistoryEventDate - pht.HistoryDate))) FILTER (WHERE pht.PostHistoryTypeId IN (10, 12)) AS MinTimeUntilClosureOrDeletionSeconds, -- Time between events
    -- Correlated Subquery: Check if the user has a 'Gold' badge for any of the post's associated tags
    (
        SELECT COUNT(b_sub.Id)
        FROM Badges b_sub
        JOIN Tags t_sub ON b_sub.Name = t_sub.TagName
        WHERE b_sub.UserId = um.UserId
          AND b_sub.Class = 1
          AND b_sub.TagBased = TRUE
          AND LOWER(t_sub.TagName) IN (SELECT LOWER(TRIM(UNNEST(string_to_array(pes.AssociatedTags, ',')))) WHERE pes.AssociatedTags IS NOT NULL)
    ) AS GoldTagBadgesForPostTagsCount,
    -- Complex Calculation: Overall User Influence Score
    CAST(
        (um.Reputation * 0.7)
        + (um.UpVotes - um.DownVotes) * 0.1
        + COALESCE(um.UserProfileViews, 0) * 0.05
        + (pes.PostScore * 0.3)
        + (COALESCE(pes.PostViewCount, 0) * 0.02)
        + (COALESCE(pes.PostCommentCount, 0) * 0.08)
        + (COALESCE(pes.PostFavoriteCount, 0) * 0.1)
        + (COALESCE(pes.AvgPositiveAnswerScoreForThisPost, 0) * 0.15)
        + (COALESCE(pla.LinkedPostsCount, 0) * 0.05)
        + (COALESCE(ucom.TotalUserCommentScore, 0) * 0.03)
        + (CASE WHEN pes.AcceptedAnswerRefId IS NOT NULL THEN 20 ELSE 0 END) -- Bonus for accepted answer
        + (CASE WHEN pes.PostTypeCategory = 'Question' AND pes.PostCommentCount > 10 THEN 15 ELSE 0 END) -- Bonus for highly discussed questions
        - (CASE WHEN MAX(CASE WHEN pht.HistoryTypeName = 'Post Closed' THEN 1 ELSE 0 END) = 1 THEN 10 ELSE 0 END) -- Penalty for closed posts
    AS NUMERIC(15, 2)) AS UserInfluenceScore
FROM
    UserMetrics um
INNER JOIN -- Only consider users who have a top-performing post
    PostEngagementSummary pes ON um.UserId = pes.OwnerUserId
LEFT JOIN
    PostLinkAnalysis pla ON pes.PostId = pla.PostId
LEFT JOIN
    PostHistoryTimeline pht ON pes.PostId = pht.PostId
LEFT JOIN
    UserCommentActivity ucom ON um.UserId = ucom.UserId
WHERE
    um.GlobalReputationRank <= 10000 -- Focus on top N users globally
    AND pes.UserPostRank = 1 -- Only their single best performing question/answer
    AND (pes.PostCreationDate BETWEEN um.UserCreationDate AND um.UserCreationDate + INTERVAL '5 years') -- Post created within 5 years of user creation
    AND LENGTH(TRIM(COALESCE(um.UserName, ''))) > 1 -- Ensure non-empty username
    AND (
        (pes.PostTypeCategory = 'Question' AND pes.AssociatedTags LIKE '%<sql>%' OR pes.AssociatedTags LIKE '%<database>%')
        OR
        (pes.PostTypeCategory = 'Answer' AND pes.AssociatedTags LIKE '%<java>%' OR pes.AssociatedTags LIKE '%<c#>%')
    ) -- Specific tag interest for questions/answers
GROUP BY
    um.UserId, um.UserName, um.Reputation, um.ReputationTier, um.GlobalReputationRank, um.UserLocation, um.TotalBadges, um.GoldBadges,
    pes.PostId, pes.PostTitle, pes.PostTypeCategory, pes.PostScore, pes.PostViewCount, pes.PostCommentCount, pes.PostFavoriteCount,
    pes.AssociatedTags, pes.AvgPositiveAnswerScoreForThisPost, pes.AcceptedAnswerRefId,
    pla.LinkedPostsCount, pla.DuplicatePostsCount, pla.LinkTypeNames,
    ucom.TotalUserComments, ucom.TotalUserCommentScore, ucom.AvgUserCommentScore, ucom.CommentScoreQuintile,
    um.UpVotes, um.DownVotes, um.UserProfileViews, um.UserCreationDate
ORDER BY
    UserInfluenceScore DESC, um.Reputation DESC, pes.PostScore DESC
LIMIT 750;