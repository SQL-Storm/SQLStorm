-- {"query": "59050.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 1244} 
SELECT 
    p.Id as PostId,
    p.Title,
    p.Body,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    u.DisplayName as OwnerDisplayName,
    p.LastActivityDate,
    p.Tags,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.PostTypeId,
    pt.Name as PostTypeName,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 3 THEN 'Wiki'
        WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
        WHEN p.PostTypeId = 5 THEN 'TagWiki'
        WHEN p.PostTypeId = 6 THEN 'ModeratorNomination'
        WHEN p.PostTypeId = 7 THEN 'WikiPlaceholder'
        WHEN p.PostTypeId = 8 THEN 'PrivilegeWiki'
    END as PostTypeDescription,
    COALESCE(p.AcceptedAnswerId, 0) as AcceptedAnswerId,
    COALESCE(p.ParentId, 0) as ParentId,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN p.ParentId IS NOT NULL THEN 'Answer'
        ELSE 'Question'
    END as PostStatus,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) as CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) as UpVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) as DownVotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 5) as FavoriteCount,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.TagBased = 0) as UserBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = p.OwnerUserId AND b.TagBased = 1) as TagBadges,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = p.OwnerUserId AND p2.PostTypeId = 1) as UserQuestions,
    (SELECT COUNT(*) FROM Posts p3 WHERE p3.OwnerUserId = p.OwnerUserId AND p3.PostTypeId = 2) as UserAnswers,
    (SELECT COUNT(*) FROM Posts p4 WHERE p4.OwnerUserId = p.OwnerUserId AND p4.PostTypeId IN (3,4,5)) as UserWikiEdits,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (1,2,3)) as EditCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10,11,12,13)) as ModActionCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 1) as LinkCount,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) as DuplicateCount,
    (SELECT AVG(v.BountyAmount) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 8) as AvgBountyAmount,
    (SELECT MAX(v.CreationDate) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId IN (8,9)) as BountyEndDate,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId = 24) as SuggestedEditCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (33,34)) as PostNoticeCount,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (35,36)) as MigrationCount,
    (SELECT COUNT(*) FROM Posts p5 WHERE p5.ParentId = p.Id AND p5.PostTypeId = 2 AND p5.Score > 0) as HighScoreAnswers,
    (SELECT COUNT(*) FROM Posts p6 WHERE p6.ParentId = p.Id AND p6.PostTypeId = 2) as TotalAnswers,
    (SELECT STRING_AGG(t.TagName, ', ') FROM (SELECT UNNEST(string_to_array(p.Tags, '><')) AS TagName) t) as TagList,
    (SELECT STRING_AGG(DISTINCT c.Text, '; ') FROM Comments c WHERE c.PostId = p.Id LIMIT 5) as SampleComments,
    (SELECT STRING_AGG(DISTINCT ph.Text, ' | ') FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (1,2,3,4,5,6) LIMIT 3) as EditSummary,
    (SELECT COALESCE(MAX(ph.CreationDate), p.CreationDate) FROM PostHistory ph WHERE ph.PostId = p.Id) as LastEditDate,
    (SELECT COALESCE(MAX(ph.CreationDate), p.CreationDate) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (10,11)) as LastModActionDate
FROM Posts p
JOIN PostTypes pt ON p.PostTypeId = pt.Id
JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId IN (1,2) 
    AND p.CreationDate >= '2022-01-01'
    AND p.Score >= 0
    AND (p.ClosedDate IS NULL OR p.ClosedDate >= '2022-01-01')
    AND p.ViewCount >= 100
ORDER BY 
    p.Score DESC,
    p.ViewCount DESC,
    p.CreationDate DESC
LIMIT 10000;