-- {"query": "4361.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 1758} 

WITH RankedPostEdits AS (
    SELECT
        ph.PostId,
        ph.UserId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId, ph.PostHistoryTypeId ORDER BY ph.CreationDate DESC) as rn
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6) -- Edits: Title, Body, Tags
),
UserPostActivity AS (
    SELECT
        p.OwnerUserId,
        p.Id AS PostId,
        p.PostTypeId,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.ViewCount AS PostViewCount,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.LastActivityDate,
        CASE WHEN p.ClosedDate IS NOT NULL THEN 1 ELSE 0 END AS IsClosed,
        CASE WHEN p.CommunityOwnedDate IS NOT NULL THEN 1 ELSE 0 END AS IsCommunityOwned,
        u.Reputation,
        u.CreationDate AS UserCreationDate,
        DATEDIFF(day, u.CreationDate, p.CreationDate) AS DaysSinceUserCreation,
        DATEDIFF(day, p.CreationDate, p.LastActivityDate) AS DaysSincePostCreationToLastActivity,
        STRING_SPLIT(p.Tags, '><') AS PostTags
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.PostTypeId = 1 -- Only Questions
),
LatestEdits AS (
    SELECT
        rpe.PostId,
        MAX(CASE WHEN rpe.PostHistoryTypeId = 4 THEN rpe.CreationDate ELSE NULL END) AS LatestTitleEditDate,
        MAX(CASE WHEN rpe.PostHistoryTypeId = 5 THEN rpe.CreationDate ELSE NULL END) AS LatestBodyEditDate,
        MAX(CASE WHEN rpe.PostHistoryTypeId = 6 THEN rpe.CreationDate ELSE NULL END) AS LatestTagsEditDate
    FROM RankedPostEdits rpe
    WHERE rpe.rn = 1
    GROUP BY rpe.PostId
),
PostVoteSummary AS (
    SELECT
        v.PostId,
        COUNT(CASE WHEN vv.Name = 'UpMod' THEN 1 ELSE NULL END) AS UpVoteCount,
        COUNT(CASE WHEN vv.Name = 'DownMod' THEN 1 ELSE NULL END) AS DownVoteCount,
        COUNT(CASE WHEN vv.Name = 'Favorite' THEN 1 ELSE NULL END) AS FavoriteVoteCount
    FROM Votes v
    JOIN VoteTypes vv ON v.VoteTypeId = vv.Id
    GROUP BY v.PostId
),
TopTagsByScore AS (
    SELECT
        t.TagName,
        AVG(upa.PostScore) AS AverageTagScore,
        SUM(upa.PostScore) AS TotalTagScore,
        COUNT(upa.PostId) AS TagPostCount
    FROM UserPostActivity upa
    CROSS APPLY upa.PostTags
    JOIN Tags t ON t.TagName = value
    GROUP BY t.TagName
    HAVING COUNT(upa.PostId) > 100 -- Consider tags with at least 100 questions
),
FinalPostData AS (
    SELECT
        upa.*,
        le.LatestTitleEditDate,
        le.LatestBodyEditDate,
        le.LatestTagsEditDate,
        pvs.UpVoteCount,
        pvs.DownVoteCount,
        pvs.FavoriteVoteCount,
        COALESCE(pvs.UpVoteCount, 0) - COALESCE(pvs.DownVoteCount, 0) AS NetVoteScore,
        CASE WHEN le.LatestTitleEditDate IS NOT NULL THEN DATEDIFF(day, upa.PostCreationDate, le.LatestTitleEditDate) ELSE NULL END AS DaysToFirstTitleEdit,
        CASE WHEN le.LatestBodyEditDate IS NOT NULL THEN DATEDIFF(day, upa.PostCreationDate, le.LatestBodyEditDate) ELSE NULL END AS DaysToFirstBodyEdit,
        CASE WHEN le.LatestTagsEditDate IS NOT NULL THEN DATEDIFF(day, upa.PostCreationDate, le.LatestTagsEditDate) ELSE NULL END AS DaysToFirstTagsEdit,
        CASE WHEN upa.LastActivityDate < DATEADD(day, -365, GETDATE()) THEN 1 ELSE 0 END AS IsOlderThanAYear
    FROM UserPostActivity upa
    LEFT JOIN LatestEdits le ON upa.PostId = le.PostId
    LEFT JOIN PostVoteSummary pvs ON upa.PostId = pvs.PostId
)
SELECT
    fpd.PostId,
    fpd.OwnerUserId,
    fpd.Reputation AS OwnerReputation,
    fpd.UserCreationDate AS OwnerCreationDate,
    fpd.DaysSinceUserCreation,
    fpd.PostCreationDate,
    fpd.PostScore,
    fpd.PostViewCount,
    fpd.AnswerCount,
    fpd.CommentCount,
    fpd.FavoriteCount,
    fpd.LastActivityDate,
    fpd.IsClosed,
    fpd.IsCommunityOwned,
    fpd.NetVoteScore,
    fpd.DaysToFirstTitleEdit,
    fpd.DaysToFirstBodyEdit,
    fpd.DaysToFirstTagsEdit,
    fpd.IsOlderThanAYear,
    CASE
        WHEN fpd.PostScore > 100 AND fpd.AnswerCount > 10 AND fpd.CommentCount < 5 THEN 'High Engagement Potential'
        WHEN fpd.PostScore < 0 AND fpd.IsClosed = 1 THEN 'Potentially Bad Question'
        WHEN fpd.DaysSinceUserCreation < 7 AND fpd.OwnerReputation < 100 THEN 'New User, Low Reputation'
        ELSE 'Standard'
    END AS PostQualityIndicator,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = fpd.PostId AND c.Score > 0) AS PositiveCommentCount,
    COALESCE(tts.AverageTagScore, 0) AS RelatedTagAverageScore,
    CASE
        WHEN fpd.PostTags IS NULL THEN 'No Tags'
        ELSE STRING_AGG(fpd.PostTags, ', ') WITHIN GROUP (ORDER BY fpd.PostTags)
    END AS FormattedTags
FROM FinalPostData fpd
LEFT JOIN TopTagsByScore tts ON EXISTS (SELECT 1 FROM fpd.PostTags pt WHERE pt = tts.TagName)
GROUP BY
    fpd.PostId,
    fpd.OwnerUserId,
    fpd.Reputation,
    fpd.UserCreationDate,
    fpd.DaysSinceUserCreation,
    fpd.PostCreationDate,
    fpd.PostScore,
    fpd.PostViewCount,
    fpd.AnswerCount,
    fpd.CommentCount,
    fpd.FavoriteCount,
    fpd.LastActivityDate,
    fpd.IsClosed,
    fpd.IsCommunityOwned,
    fpd.NetVoteScore,
    fpd.DaysToFirstTitleEdit,
    fpd.DaysToFirstBodyEdit,
    fpd.DaysToFirstTagsEdit,
    fpd.IsOlderThanAYear,
    tts.AverageTagScore
HAVING COUNT(fpd.PostId) > 5 -- Ensure we only consider posts that have been part of at least 5 tag analyses (implying tag existence)
ORDER BY fpd.PostScore DESC, fpd.LastActivityDate DESC
LIMIT 1000;
