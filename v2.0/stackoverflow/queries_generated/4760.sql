-- {"query": "4760.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gemini-2.5-flash-lite", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2111, "output_tokens": 933} 

WITH RankedPosts AS (
    SELECT
        p.Id AS PostId,
        p.Title,
        p.OwnerUserId,
        u.DisplayName AS OwnerDisplayName,
        p.CreationDate AS PostCreationDate,
        p.Score AS PostScore,
        p.AnswerCount,
        p.CommentCount,
        ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate DESC) AS PostNumberForUser,
        LAG(p.Score, 1, 0) OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS PreviousPostScore,
        COALESCE(u.UpVotes, 0) AS UserUpVotes,
        COALESCE(u.DownVotes, 0) AS UserDownVotes,
        CASE
            WHEN p.PostTypeId = 1 THEN 'Question'
            WHEN p.PostTypeId = 2 THEN 'Answer'
            ELSE 'Other'
        END AS PostTypeDescription
    FROM Posts p
    LEFT JOIN Users u ON p.OwnerUserId = u.Id
    WHERE p.CreationDate >= DATE('now', '-1 year')
      AND p.Score > 0
      AND p.OwnerUserId IS NOT NULL
),
UserPostSummary AS (
    SELECT
        rp.OwnerUserId,
        COUNT(rp.PostId) AS TotalPosts,
        SUM(rp.PostScore) AS TotalScore,
        AVG(rp.PostScore) AS AverageScore,
        MAX(rp.PostScore) AS MaxScore,
        SUM(rp.AnswerCount) AS TotalAnswersGiven,
        AVG(rp.CommentCount) AS AverageComments
    FROM RankedPosts rp
    GROUP BY rp.OwnerUserId
),
PostLinkAnalysis AS (
    SELECT
        pl.PostId,
        COUNT(DISTINCT pl.RelatedPostId) AS LinkedPostCount,
        STRING_AGG(lt.Name || ': ' || CAST(pl.RelatedPostId AS TEXT), ', ') AS LinkDetails
    FROM PostLinks pl
    JOIN LinkTypes lt ON pl.LinkTypeId = lt.Id
    WHERE pl.CreationDate >= DATE('now', '-1 year')
    GROUP BY pl.PostId
)
SELECT
    rp.PostId,
    rp.Title,
    rp.PostTypeDescription,
    rp.PostCreationDate,
    rp.PostScore,
    rp.PostNumberForUser,
    rp.PreviousPostScore,
    rp.UserUpVotes,
    rp.UserDownVotes,
    ups.TotalPosts AS UserTotalPosts,
    ups.AverageScore AS UserAverageScore,
    ups.TotalAnswersGiven AS UserTotalAnswersGiven,
    ups.AverageComments AS UserAverageComments,
    COALESCE(pla.LinkedPostCount, 0) AS PostLinkedCount,
    pla.LinkDetails,
    CASE
        WHEN rp.PostScore > ups.AverageScore * 1.5 THEN 'Above Average'
        WHEN rp.PostScore < ups.AverageScore * 0.5 THEN 'Below Average'
        ELSE 'Average'
    END AS ScoreRelativeToUserAverage,
    CASE
        WHEN rp.PostNumberForUser <= 5 THEN 'Early Career'
        WHEN rp.PostNumberForUser <= 50 THEN 'Mid Career'
        ELSE 'Experienced'
    END AS UserPostCareerStage,
    CASE
        WHEN rp.OwnerUserId IN (SELECT UserId FROM Votes WHERE VoteTypeId = 16) THEN 'HasApprovedEdit'
        ELSE 'NoApprovedEdit'
    END AS UserEditApprovalStatus,
    rp.OwnerDisplayName || ' (ID: ' || rp.OwnerUserId || ')' AS OwnerInfo
FROM RankedPosts rp
JOIN UserPostSummary ups ON rp.OwnerUserId = ups.OwnerUserId
LEFT JOIN PostLinkAnalysis pla ON rp.PostId = pla.PostId
WHERE rp.PostNumberForUser <= 10
  AND ups.TotalScore > 1000
  AND (rp.UserUpVotes - rp.UserDownVotes) > 500
ORDER BY ups.AverageScore DESC, rp.PostScore DESC
LIMIT 100;
