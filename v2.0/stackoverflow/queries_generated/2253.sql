-- {"query": "2253.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1463} 
WITH RecursiveCTE AS (
    SELECT p.Id, p.Title, p.CreationDate, p.Score,
           ARRAY_REMOVE(STRING_TO_ARRAY(SUBSTRING(p.Tags FROM 2 FOR LENGTH(p.Tags) - 2), '><'), '') AS TagArray,
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
           COALESCE(COUNT(DISTINCT b.Id),0) AS BadgesCount,
           MAX(b.Date) AS LastBadgeDate,
           RANK() OVER (ORDER BY COALESCE(SUM(p.Score),0) DESC) AS UserScoreRank
    FROM Users u
    LEFT JOIN Posts p ON p.OwnerUserId = u.Id
    LEFT JOIN Badges b ON b.UserId = u.Id
    GROUP BY u.Id, u.DisplayName
),
TagBadges AS (
    SELECT b.UserId, b.TagBased, b.Name, COUNT(*) AS BadgeCount
    FROM Badges b
    WHERE b.TagBased = 1
    GROUP BY b.UserId, b.TagBased, b.Name
),
PostCloseInfo AS (
    SELECT ph.PostId,
           MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.CreationDate ELSE NULL END) AS CloseDate,
           MAX(CASE WHEN ph.PostHistoryTypeId = 11 THEN ph.CreationDate ELSE NULL END) AS ReopenDate,
           MAX(CASE WHEN ph.PostHistoryTypeId = 10 THEN ph.Comment ELSE NULL END) AS CloseReasonId
    FROM PostHistory ph
    GROUP BY ph.PostId
),
LinkedDuplicates AS (
    SELECT pl.PostId, pl.RelatedPostId, lt.Name AS LinkTypeName
    FROM PostLinks pl
    JOIN LinkTypes lt ON lt.Id = pl.LinkTypeId
    WHERE pl.LinkTypeId = 3
),
PostStats AS (
    SELECT p.Id,
           p.Title,
           p.OwnerUserId,
           COALESCE(av.UpVotes, 0) AS UpVotes,
           COALESCE(av.DownVotes, 0) AS DownVotes,
           COALESCE(av.TotalBounty, 0) AS TotalBounty,
           COALESCE(cinfo.CloseDate, NULL) AS CloseDate,
           COALESCE(cinfo.ReopenDate, NULL) AS ReopenDate,
           cinfo.CloseReasonId,
           u.DisplayName AS OwnerDisplayName,
           ROW_NUMBER() OVER (PARTITION BY p.OwnerUserId ORDER BY p.Score DESC) AS PostRankByOwner
    FROM Posts p
    LEFT JOIN AggregatedVotes av ON av.PostId = p.Id
    LEFT JOIN PostCloseInfo cinfo ON cinfo.PostId = p.Id
    LEFT JOIN Users u ON u.Id = p.OwnerUserId
    WHERE p.PostTypeId IN (1,2)
),
RecentActivity AS (
    SELECT p.Id AS PostId, MAX(ph.CreationDate) AS LastEditDate, COUNT(DISTINCT ph.PostHistoryTypeId) AS EditCount
    FROM Posts p
    LEFT JOIN PostHistory ph ON ph.PostId = p.Id
    WHERE ph.PostHistoryTypeId IN (4,5,6,7,8,9)
    GROUP BY p.Id
),
ComplexFilter AS (
    SELECT r.PostId, r.LastEditDate, r.EditCount, ps.Title, ps.UpVotes, ps.DownVotes, ps.TotalBounty, ps.CloseDate, ps.OwnerDisplayName,
           ARRAY_TO_STRING(ARRAY(SELECT UNNEST(RecursiveCTE.TagArray) WHERE LENGTH(UNNEST) > 2), ', ') AS FilteredTags,
           ROW_NUMBER() OVER (ORDER BY r.EditCount DESC, ps.UpVotes DESC, ps.CloseDate NULLS LAST) AS FinalRank
    FROM RecentActivity r
    JOIN PostStats ps ON ps.Id = r.PostId
    JOIN RecursiveCTE ON RecursiveCTE.Id = r.PostId
    WHERE ps.CloseDate IS NULL
      AND r.EditCount > 1
      AND ps.UpVotes > ps.DownVotes * 2
      AND (ps.TotalBounty > 100 OR ps.TotalBounty = 0)
)
SELECT cf.FinalRank,
       cf.Title,
       cf.OwnerDisplayName,
       cf.UpVotes,
       cf.DownVotes,
       cf.TotalBounty,
       cf.LastEditDate,
       cf.EditCount,
       cf.FilteredTags,
       ua.QuestionsCount,
       ua.AnswersCount,
       ua.BadgesCount,
       ua.LastBadgeDate,
       COALESCE(tb.BadgeCount, 0) AS TagBadgeCount
FROM ComplexFilter cf
LEFT JOIN UserActivity ua ON ua.DisplayName = cf.OwnerDisplayName
LEFT JOIN TagBadges tb ON tb.UserId = ua.Id
WHERE cf.FinalRank <= 50
UNION
SELECT rnk, title, owner, upv, downv, bounty, led, edcnt, tags, qcnt, acnt, bcnt, lbd, 0
FROM (
    SELECT ROW_NUMBER() OVER (ORDER BY Score DESC, CreationDate) AS rnk,
           Title as title,
           COALESCE(OwnerDisplayName, 'Community') as owner,
           COALESCE(UpVotes,0) as upv,
           COALESCE(DownVotes,0) as downv,
           COALESCE(TotalBounty,0) as bounty,
           COALESCE(LastEditDate, CreationDate) as led,
           COALESCE(EditCount,0) as edcnt,
           NULL::varchar as tags,
           0 as qcnt,
           0 as acnt,
           0 as bcnt,
           NULL::timestamp as lbd
    FROM Posts p
    LEFT JOIN AggregatedVotes av ON av.PostId = p.Id
    LEFT JOIN RecentActivity ra ON ra.PostId = p.Id
    WHERE p.PostTypeId = 2
    LIMIT 10
) AS TopAnswers
ORDER BY FinalRank NULLS LAST, FinalRank IS NULL;