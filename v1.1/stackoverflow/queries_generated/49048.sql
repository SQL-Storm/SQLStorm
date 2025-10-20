-- {"query": "49048.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "gemini-2.5-flash", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2074, "output_tokens": 972} 
WITH GoldBadgeUsers AS (
    SELECT DISTINCT
        b.UserId
    FROM Badges b
    WHERE b.Class = 1 -- Gold badges
),
UserPostScores AS (
    SELECT
        p.OwnerUserId,
        SUM(p.Score) AS TotalPostScore,
        COUNT(p.Id) AS TotalPosts
    FROM Posts p
    JOIN GoldBadgeUsers gbu ON p.OwnerUserId = gbu.UserId
    WHERE p.PostTypeId IN (1, 2) -- Questions or Answers
      AND p.CreationDate >= (CURRENT_DATE - INTERVAL '5 years')
    GROUP BY p.OwnerUserId
    HAVING COUNT(p.Id) > 0 -- Ensure user has posts in this period
),
UserCommentScores AS (
    SELECT
        c.UserId,
        SUM(c.Score) AS TotalCommentScore
    FROM Comments c
    JOIN GoldBadgeUsers gbu ON c.UserId = gbu.UserId
    GROUP BY c.UserId
    HAVING SUM(c.Score) >= 5 -- At least 5 upvotes on comments
),
PostEditCounts AS (
    SELECT
        ph.PostId,
        COUNT(DISTINCT ph.RevisionGUID) AS EditCount
    FROM PostHistory ph
    WHERE ph.PostHistoryTypeId IN (4, 5, 6, 7, 8, 9, 24) -- Edit Title, Body, Tags, Rollback Title/Body/Tags, Suggested Edit Applied
    GROUP BY ph.PostId
),
UserMostEditedPost AS (
    SELECT
        p.OwnerUserId,
        MAX(pec.EditCount) AS MaxEditsOnSinglePost
    FROM Posts p
    JOIN PostEditCounts pec ON p.Id = pec.PostId
    JOIN GoldBadgeUsers gbu ON p.OwnerUserId = gbu.UserId
    WHERE p.PostTypeId IN (1, 2) -- Consider questions or answers
      AND pec.EditCount >= 3 -- At least 3 edits
    GROUP BY p.OwnerUserId
),
UserIndividualTags AS (
    SELECT
        p.OwnerUserId AS UserId,
        UNNEST(string_to_array(SUBSTRING(p.Tags, 2, LENGTH(p.Tags) - 2), '><')) AS TagName
    FROM Posts p
    JOIN GoldBadgeUsers gbu ON p.OwnerUserId = gbu.UserId
    WHERE p.PostTypeId = 1 -- Only consider tags from questions
      AND p.Tags IS NOT NULL
      AND LENGTH(p.Tags) > 2
),
UserTagCounts AS (
    SELECT
        uit.UserId,
        uit.TagName,
        COUNT(*) AS TagCount
    FROM UserIndividualTags uit
    WHERE uit.TagName IS NOT NULL AND uit.TagName != ''
    GROUP BY uit.UserId, uit.TagName
),
RankedUserTags AS (
    SELECT
        utc.UserId,
        utc.TagName,
        utc.TagCount,
        ROW_NUMBER() OVER (PARTITION BY utc.UserId ORDER BY utc.TagCount DESC, utc.TagName ASC) as rn
    FROM UserTagCounts utc
),
UserTop3Tags AS (
    SELECT
        rut.UserId,
        STRING_AGG(rut.TagName, ', ' ORDER BY rut.rn) AS Top3Tags
    FROM RankedUserTags rut
    WHERE rut.rn <= 3
    GROUP BY rut.UserId
)
SELECT
    u.Id AS UserId,
    u.DisplayName,
    ups.TotalPostScore,
    (ups.TotalPostScore * 1.0 / ups.TotalPosts) AS AveragePostScore,
    ucs.TotalCommentScore,
    umep.MaxEditsOnSinglePost,
    utt.Top3Tags
FROM Users u
JOIN UserPostScores ups ON u.Id = ups.OwnerUserId
JOIN UserCommentScores ucs ON u.Id = ucs.UserId
JOIN UserMostEditedPost umep ON u.Id = umep.OwnerUserId
LEFT JOIN UserTop3Tags utt ON u.Id = utt.UserId -- Use LEFT JOIN in case a user has no questions with tags
ORDER BY
    ups.TotalPostScore DESC,
    ucs.TotalCommentScore DESC,
    umep.MaxEditsOnSinglePost DESC,
    u.Id ASC
LIMIT 100;