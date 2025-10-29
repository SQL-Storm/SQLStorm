-- {"query": "5333.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5-nano", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 1072} 
WITH
-- CTE to compute a rich set of post analytics per post
PostAnalytics AS (
    SELECT
        p.Id AS PostId,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.LastActivityDate,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.Tags,
        p.FavoriteCount,
        p.AnswerCount,
        COALESCE(p.CommentCount, 0) AS CommentCount,
        CASE
            WHEN p.OwnerUserId IS NULL THEN 'Unknown'
            ELSE u.DisplayName
        END AS OwnerDisplayName,
        -- Total upvotes and downvotes from Votes if present
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id), 0) AS UpVotesForPost,
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 3 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id), 0) AS DownVotesForPost,
        -- Complex derived metric: engagement score with null-safe arithmetic
        COALESCE(p.ViewCount,0) * 2 +
        COALESCE(SUM(CASE WHEN v.VoteTypeId = 2 THEN 1 ELSE 0 END) OVER (PARTITION BY p.Id),0) * 3 +
        COALESCE(p.CommentCount,0) * 5 AS EngagementScore
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    LEFT JOIN Votes v ON p.Id = v.PostId
),
-- Subquery: latest edits per post from PostHistory
LatestEdits AS (
    SELECT
        ph.PostId,
        ph.Id AS HistoryId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ph.UserId,
        ph.Comment,
        ph.Text,
        ROW_NUMBER() OVER (PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4,5,6,16,36) -- common edit/ownership-related histories
),
-- Windowed ranking of related posts by activity and score
RelatedRanking AS (
    SELECT
        pl.Id AS LinkId,
        pl.PostId,
        pl.RelatedPostId,
        l.Name AS LinkTypeName,
        p2.Title AS RelatedTitle,
        p2.Score AS RelatedScore,
        p2.ViewCount AS RelatedViews,
        ROW_NUMBER() OVER (PARTITION BY pl.PostId ORDER BY p2.Score DESC, p2.ViewCount DESC) AS Rank
    FROM PostLinks pl
    JOIN Posts p2 ON pl.RelatedPostId = p2.Id
    JOIN LinkTypes l ON pl.LinkTypeId = l.Id
    WHERE l.Name IN ('Linked','Duplicate')
),
-- Final composite: join analytics with latest edits and related ranking; add NULL-safe predicates and complex filters
Final AS (
    SELECT
        pa.PostId,
        pa.PostTypeId,
        pa.Title,
        pa.CreationDate,
        pa.LastActivityDate,
        pa.Score,
        pa.ViewCount,
        pa.OwnerUserId,
        pa.Tags,
        pa.FavoriteCount,
        pa.AnswerCount,
        pa.CommentCount,
        pa.OwnerDisplayName,
        pa.UpVotesForPost,
        pa.DownVotesForPost,
        pa.EngagementScore,
        le.HistoryId AS LatestEditHistoryId,
        le.PostHistoryTypeId AS LatestEditType,
        le.CreationDate AS LatestEditDate,
        le.UserId AS LatestEditorUserId,
        le.Comment AS LatestEditComment,
        le.Text AS LatestEditText,
        rr.RelatedPostId,
        rr.RelatedTitle,
        rr.RelatedScore,
        rr.RelatedViews,
        rr.Rank
    FROM PostAnalytics pa
    LEFT JOIN LatestEdits le ON le.PostId = pa.PostId AND le.rn = 1
    LEFT JOIN RelatedRanking rr ON rr.PostId = pa.PostId AND rr.Rank = 1
    WHERE
        -- Complex predicate: posts that are either popular by engagement or have recent edits
        (pa.EngagementScore > 100 OR le.LatestEditDate IS NOT NULL)
        -- And exclude community wiki placeholders to avoid trivial data
        AND pa.Title IS NOT NULL
)
SELECT
    PostId,
    PostTypeId,
    Title,
    CreationDate,
    LastActivityDate,
    Score,
    ViewCount,
    OwnerUserId,
    Tags,
    FavoriteCount,
    AnswerCount,
    CommentCount,
    OwnerDisplayName,
    UpVotesForPost,
    DownVotesForPost,
    EngagementScore,
    LatestEditHistoryId,
    LatestEditType,
    LatestEditDate,
    LatestEditorUserId,
    LatestEditComment,
    LatestEditText,
    RelatedPostId,
    RelatedTitle,
    RelatedScore,
    RelatedViews,
    Rank
FROM Final
ORDER BY EngagementScore DESC NULLS LAST, LastActivityDate DESC
LIMIT 200;