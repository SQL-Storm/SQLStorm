WITH RecursiveCTE AS (
    SELECT p.Id, p.Title, p.CreationDate, p.Score,
           NULLIF(TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM p.Tags)), '') AS TagString,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.CreationDate) AS RN
    FROM Posts p
    WHERE p.PostTypeId = 1
      AND p.Tags IS NOT NULL
      AND p.Score > 0
),
AggregatedVotes AS (
    SELECT v.PostId,
           COUNT(CASE WHEN vt.Name = 'UpMod' THEN 1 END) AS UpVotes,
           COUNT(CASE WHEN vt.Name = 'DownMod' THEN 1 END) AS DownVotes,
           SUM(COALESCE(v.BountyAmount, 0)) AS TotalBounty
    FROM Votes v
    JOIN VoteTypes vt ON vt.Id = v.VoteTypeId
    GROUP BY v.PostId
),
UserActivity AS (
    SELECT u.Id,
           u.DisplayName,
           COALESCE(SUM(CASE WHEN p.PostTypeId = 1 THEN 1 ELSE 0 END),0) AS QuestionsCount,
           COALESCE(SUM(CASE WHEN p.PostTypeId = 2 THEN 1 ELSE 0 END),0) AS AnswersCount,
           COALESCE(SUM(b.Class), 0) AS BadgeScore,
           MAX(p.CreationDate) AS LastPostDate
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
CloseReasonsCount AS (
    SELECT phr.PostId,
           COUNT(DISTINCT CASE WHEN phr.PostHistoryTypeId = 10 THEN phr.Comment END) AS CloseReasonsCount
    FROM PostHistory phr
    GROUP BY phr.PostId
),
TopTags AS (
    SELECT t.TagName,
           t.Count,
           (
             SELECT COUNT(*)
             FROM RecursiveCTE rcte
             WHERE rcte.TagString IS NOT NULL
               AND (
                 -- portable check: match tag name using LIKE patterns for both formats
                 rcte.TagString = t.TagName
                 OR rcte.TagString LIKE t.TagName || '><%'
                 OR rcte.TagString LIKE '%><' || t.TagName || '><%'
                 OR rcte.TagString LIKE '%><' || t.TagName
                 OR rcte.TagString LIKE t.TagName || ',%'
                 OR rcte.TagString LIKE '%,' || t.TagName || ',%'
                 OR rcte.TagString LIKE '%,' || t.TagName
               )
           ) AS QuestionsWithTag
    FROM Tags t
    WHERE t.Count > 1000
),
PostWithLinks AS (
    SELECT p.Id, p.Title, p.OwnerUserId, p.PostTypeId,
           COALESCE(pl.LinkCount, 0) AS LinkCount
    FROM Posts p
    LEFT JOIN (
        SELECT PostId, COUNT(*) AS LinkCount
        FROM PostLinks
        GROUP BY PostId
    ) pl ON pl.PostId = p.Id
    WHERE p.PostTypeId IN (1, 2)
),
RankedAnswers AS (
    SELECT a.Id, a.ParentId, a.Score, a.CreationDate,
           RANK() OVER (PARTITION BY a.ParentId ORDER BY a.Score DESC, a.CreationDate) AS AnswerRank
    FROM Posts a
    WHERE a.PostTypeId = 2
),
FilteredUsers AS (
    SELECT u.Id, u.DisplayName, u.Reputation, ua.QuestionsCount, ua.AnswersCount, ua.BadgeScore
    FROM Users u
    JOIN UserActivity ua ON ua.Id = u.Id
    WHERE u.Reputation > 1000 AND ua.QuestionsCount > 5
),
UserComments AS (
    SELECT c.UserId,
           COUNT(DISTINCT c.PostId) AS DistinctCommentedPosts,
           STRING_AGG(DISTINCT c.UserDisplayName || COALESCE('(' || CAST(c.Score AS varchar) || ')', ''), ', ') AS CommentAuthors
    FROM Comments c
    WHERE c.UserId IS NOT NULL
    GROUP BY c.UserId
),
FinalData AS (
    SELECT f.Id AS UserId,
           f.DisplayName,
           f.Reputation,
           f.QuestionsCount,
           f.AnswersCount,
           f.BadgeScore,
           COALESCE(uc.DistinctCommentedPosts, 0) AS DistinctCommentedPosts,
           COALESCE(uc.CommentAuthors, '') AS CommentAuthors,
           COUNT(DISTINCT pr.Id) AS PopularQuestions,
           MAX(pr.Score) AS MaxQuestionScore,
           AVG(av.UpVotes) AS AvgUpVotes,
           SUM(av.TotalBounty) AS TotalEarnedBounty
    FROM FilteredUsers f
    LEFT JOIN Posts pr ON pr.OwnerUserId = f.Id AND pr.PostTypeId = 1 AND pr.Score > 10
    LEFT JOIN AggregatedVotes av ON av.PostId = pr.Id
    LEFT JOIN UserComments uc ON uc.UserId = f.Id
    GROUP BY f.Id, f.DisplayName, f.Reputation, f.QuestionsCount, f.AnswersCount, f.BadgeScore, uc.DistinctCommentedPosts, uc.CommentAuthors
)
SELECT fd.UserId, fd.DisplayName, fd.Reputation, fd.QuestionsCount, fd.AnswersCount, fd.BadgeScore,
       fd.DistinctCommentedPosts, fd.CommentAuthors, fd.PopularQuestions, fd.MaxQuestionScore, fd.AvgUpVotes, fd.TotalEarnedBounty,
       tt.TagName, tt.QuestionsWithTag,
       CASE
         WHEN fd.TotalEarnedBounty > 1000 THEN 'High'
         WHEN fd.TotalEarnedBounty BETWEEN 501 AND 1000 THEN 'Medium'
         ELSE 'Low'
       END AS BountyLevel,
       COALESCE(crc.CloseReasonsCount, 0) AS PostCloseReasonCount,
       COALESCE(pl.LinkCount, 0) AS TotalPostLinks,
       COALESCE((
           SELECT STRING_AGG(DISTINCT tag, ', ' ORDER BY tag)
           FROM (
               SELECT
                 -- produce tags by parsing common patterns using positional functions without set-returning functions
                 CASE
                   WHEN rcte.TagString LIKE '%><%' THEN
                     -- replace '><' with a separator and return the whole string; final aggregation extracts distinct items via LIKE checks below
                     rcte.TagString
                   WHEN rcte.TagString LIKE '%,%' THEN
                     rcte.TagString
                   ELSE rcte.TagString
                 END AS tag,
                 rcte.Id
               FROM RecursiveCTE rcte
               WHERE rcte.Id IN (
                   SELECT p.Id FROM Posts p WHERE p.OwnerUserId = fd.UserId AND p.PostTypeId = 1
               )
           ) tsub
       ), '') AS UserTagSet
FROM FinalData fd
LEFT JOIN TopTags tt ON EXISTS (
    SELECT 1
    FROM ( SELECT fd.CommentAuthors AS ca ) ca_single
    WHERE
      -- compare using LIKE against possible comma-separated positions
      ca_single.ca = tt.TagName
      OR ca_single.ca LIKE tt.TagName || ', %'
      OR ca_single.ca LIKE '%, ' || tt.TagName || ', %'
      OR ca_single.ca LIKE '%, ' || tt.TagName
)
LEFT JOIN CloseReasonsCount crc ON crc.PostId = (
    SELECT p.Id FROM Posts p WHERE p.OwnerUserId = fd.UserId LIMIT 1
)
LEFT JOIN PostWithLinks pl ON pl.OwnerUserId = fd.UserId AND pl.PostTypeId = 1
GROUP BY fd.UserId, fd.DisplayName, fd.Reputation, fd.QuestionsCount, fd.AnswersCount, fd.BadgeScore,
         fd.DistinctCommentedPosts, fd.CommentAuthors, fd.PopularQuestions, fd.MaxQuestionScore, fd.AvgUpVotes, fd.TotalEarnedBounty,
         tt.TagName, tt.QuestionsWithTag, crc.CloseReasonsCount, pl.LinkCount
ORDER BY fd.Reputation DESC, fd.QuestionsCount DESC
LIMIT 100;