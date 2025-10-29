WITH RankedPostHistory AS (
    SELECT
        ph.PostId,
        ph.PostHistoryTypeId,
        ph.CreationDate,
        u.DisplayName AS UserDisplayName,
        ph.Comment,
        ph.UserId,
        ROW_NUMBER() OVER(PARTITION BY ph.PostId ORDER BY ph.CreationDate DESC) AS rn
    FROM PostHistory ph
    LEFT JOIN Users u ON ph.UserId = u.Id
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9)
      AND ph.UserId IS NOT NULL
),
PostEditSummary AS (
    SELECT
        rph.PostId,
        MAX(CASE WHEN rph.PostHistoryTypeId IN (4, 7) THEN 1 ELSE 0 END) AS TitleEdited,
        MAX(CASE WHEN rph.PostHistoryTypeId IN (5, 8) THEN 1 ELSE 0 END) AS BodyEdited,
        MAX(CASE WHEN rph.PostHistoryTypeId IN (6, 9) THEN 1 ELSE 0 END) AS TagsEdited,
        COUNT(DISTINCT CASE WHEN rph.PostHistoryTypeId IN (4, 7) THEN rph.UserId END) AS DistinctTitleEditors,
        COUNT(DISTINCT CASE WHEN rph.PostHistoryTypeId IN (5, 8) THEN rph.UserId END) AS DistinctBodyEditors,
        COUNT(DISTINCT CASE WHEN rph.PostHistoryTypeId IN (6, 9) THEN rph.UserId END) AS DistinctTagEditors,
        SUM(CASE WHEN rph.rn = 1 THEN 1 ELSE 0 END) AS MostRecentEditFlag
    FROM RankedPostHistory rph
    GROUP BY rph.PostId
),
UserPostCounts AS (
    SELECT
        p.OwnerUserId,
        COUNT(CASE WHEN pt.Name = 'Question' THEN p.Id END) AS QuestionCount,
        COUNT(CASE WHEN pt.Name = 'Answer' THEN p.Id END) AS AnswerCount,
        SUM(p.Score) AS TotalScore,
        AVG(CAST(p.ViewCount AS NUMERIC)) AS AverageViewCount,
        MAX(p.CreationDate) AS LastPostDate
    FROM Posts p
    JOIN PostTypes pt ON p.PostTypeId = pt.Id
    WHERE p.OwnerUserId IS NOT NULL
      AND p.OwnerUserId > 0
    GROUP BY p.OwnerUserId
)
SELECT
    p.Id AS PostId,
    pt.Name AS PostType,
    p.Title,
    u.DisplayName AS OwnerDisplayName,
    p.CreationDate AS PostCreationDate,
    p.Score,
    p.ViewCount,
    COALESCE(pes.TitleEdited, 0) AS TitleEditedFlag,
    COALESCE(pes.BodyEdited, 0) AS BodyEditedFlag,
    COALESCE(pes.TagsEdited, 0) AS TagsEditedFlag,
    pes.DistinctTitleEditors,
    pes.DistinctBodyEditors,
    pes.DistinctTagEditors,
    upc.QuestionCount,
    upc.AnswerCount,
    upc.TotalScore,
    upc.AverageViewCount,
    upc.LastPostDate,
    CASE
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN p.OwnerUserId = -1 THEN 'Community User'
        ELSE 'Active'
    END AS PostStatus,
    CASE
        WHEN u.Reputation > 100000 THEN 'Expert'
        WHEN u.Reputation > 10000 THEN 'Advanced'
        WHEN u.Reputation > 1000 THEN 'Intermediate'
        ELSE 'Beginner'
    END AS UserExperienceLevel,
    CASE
        WHEN SUBSTRING(p.Tags FROM 1 FOR 1) = '<' AND SUBSTRING(p.Tags FROM CHAR_LENGTH(p.Tags) - 1 FOR 1) = '>' AND CHAR_LENGTH(p.Tags) > 2
            THEN REPLACE(REPLACE(SUBSTRING(p.Tags FROM 2 FOR CHAR_LENGTH(p.Tags)-2), '><', ';'), '>', '')
        ELSE p.Tags
    END AS FormattedTags,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id AND c.Score > 5) AS HighScoreCommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) AS UpVoteCount,
    CASE WHEN p.OwnerUserId = (
             SELECT v2.UserId FROM Votes v2 WHERE v2.PostId = p.Id AND v2.VoteTypeId = 1 LIMIT 1
         ) THEN 'Accepted' ELSE 'Not Accepted' END AS AcceptedAnswerStatus
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN PostEditSummary pes ON p.Id = pes.PostId
LEFT JOIN UserPostCounts upc ON p.OwnerUserId = upc.OwnerUserId
WHERE p.PostTypeId IN (1, 2)
  AND p.OwnerUserId IS NOT NULL
  AND p.OwnerUserId > 0
  AND p.CreationDate >= DATE '2023-01-01'
  AND u.Reputation >= 50
ORDER BY p.LastActivityDate DESC
LIMIT 1000;