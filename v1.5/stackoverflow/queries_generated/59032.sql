-- {"query": "59032.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p2", "model": "qwen3-coder", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2061, "output_tokens": 1801} 
SELECT 
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName as OwnerDisplayName,
    u.Reputation,
    (SELECT COUNT(*) FROM Comments c WHERE c.PostId = p.Id) as CommentCount,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2) as Upvotes,
    (SELECT COUNT(*) FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 3) as Downvotes,
    (SELECT COUNT(*) FROM PostHistory ph WHERE ph.PostId = p.Id AND ph.PostHistoryTypeId IN (1, 4, 6)) as EditCount,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 3 THEN 'Wiki'
        WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
        WHEN p.PostTypeId = 5 THEN 'TagWiki'
        WHEN p.PostTypeId = 6 THEN 'ModeratorNomination'
        WHEN p.PostTypeId = 7 THEN 'WikiPlaceholder'
        WHEN p.PostTypeId = 8 THEN 'PrivilegeWiki'
    END as PostType,
    p.Tags,
    p.AnswerCount,
    p.CommentCount as ReportedCommentCount,
    p.FavoriteCount,
    p.LastActivityDate,
    p.ClosedDate,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1) as GoldBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 2) as SilverBadges,
    (SELECT COUNT(*) FROM Badges b WHERE b.UserId = u.Id AND b.Class = 3) as BronzeBadges,
    (SELECT COUNT(*) FROM Posts p2 WHERE p2.OwnerUserId = u.Id AND p2.PostTypeId = 1) as QuestionCount,
    (SELECT COUNT(*) FROM Posts p3 WHERE p3.OwnerUserId = u.Id AND p3.PostTypeId = 2) as AnswerCount,
    (SELECT AVG(p4.Score) FROM Posts p4 WHERE p4.OwnerUserId = u.Id AND p4.PostTypeId = 1) as AvgQuestionScore,
    (SELECT AVG(p5.Score) FROM Posts p5 WHERE p5.OwnerUserId = u.Id AND p5.PostTypeId = 2) as AvgAnswerScore,
    (SELECT STRING_AGG(t.TagName, ', ') FROM Tags t WHERE t.Id IN (SELECT unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><'))) ) as TagList,
    (SELECT COUNT(*) FROM PostLinks pl WHERE pl.PostId = p.Id AND pl.LinkTypeId = 3) as DuplicateCount,
    (SELECT COUNT(*) FROM PostHistory ph2 WHERE ph2.PostId = p.Id AND ph2.PostHistoryTypeId = 10 AND ph2.Comment LIKE '%101%') as DuplicateCloseCount,
    (SELECT COUNT(*) FROM PostHistory ph3 WHERE ph3.PostId = p.Id AND ph3.PostHistoryTypeId = 10 AND ph3.Comment LIKE '%102%') as OffTopicCloseCount,
    (SELECT COUNT(*) FROM PostHistory ph4 WHERE ph4.PostId = p.Id AND ph4.PostHistoryTypeId = 10 AND ph4.Comment LIKE '%103%') as NeedsClarificationCloseCount,
    (SELECT COUNT(*) FROM PostHistory ph5 WHERE ph5.PostId = p.Id AND ph5.PostHistoryTypeId = 10 AND ph5.Comment LIKE '%104%') as NeedsFocusCloseCount,
    (SELECT COUNT(*) FROM PostHistory ph6 WHERE ph6.PostId = p.Id AND ph6.PostHistoryTypeId = 10 AND ph6.Comment LIKE '%105%') as OpinionBasedCloseCount,
    (SELECT COUNT(*) FROM PostHistory ph7 WHERE ph7.PostId = p.Id AND ph7.PostHistoryTypeId = 12) as DeletedCount,
    (SELECT COUNT(*) FROM PostHistory ph8 WHERE ph8.PostId = p.Id AND ph8.PostHistoryTypeId = 13) as UndeletedCount,
    (SELECT COUNT(*) FROM PostHistory ph9 WHERE ph9.PostId = p.Id AND ph9.PostHistoryTypeId = 14) as LockedCount,
    (SELECT COUNT(*) FROM PostHistory ph10 WHERE ph10.PostId = p.Id AND ph10.PostHistoryTypeId = 15) as UnlockedCount,
    (SELECT COUNT(*) FROM PostHistory ph11 WHERE ph11.PostId = p.Id AND ph11.PostHistoryTypeId = 19) as ProtectedCount,
    (SELECT COUNT(*) FROM PostHistory ph12 WHERE ph12.PostId = p.Id AND ph12.PostHistoryTypeId = 20) as UnprotectedCount,
    (SELECT COUNT(*) FROM PostHistory ph13 WHERE ph13.PostId = p.Id AND ph13.PostHistoryTypeId = 22) as UnmergedCount,
    (SELECT COUNT(*) FROM PostHistory ph14 WHERE ph14.PostId = p.Id AND ph14.PostHistoryTypeId = 24) as SuggestedEditCount,
    (SELECT COUNT(*) FROM PostHistory ph15 WHERE ph15.PostId = p.Id AND ph15.PostHistoryTypeId = 31) as MovedToChatCount,
    (SELECT COUNT(*) FROM PostHistory ph16 WHERE ph16.PostId = p.Id AND ph16.PostHistoryTypeId = 35) as MigratedAwayCount,
    (SELECT COUNT(*) FROM PostHistory ph17 WHERE ph17.PostId = p.Id AND ph17.PostHistoryTypeId = 36) as MigratedHereCount,
    (SELECT COUNT(*) FROM PostHistory ph18 WHERE ph18.PostId = p.Id AND ph18.PostHistoryTypeId = 37) as MergeSourceCount,
    (SELECT COUNT(*) FROM PostHistory ph19 WHERE ph19.PostId = p.Id AND ph19.PostHistoryTypeId = 38) as MergeDestinationCount,
    (SELECT COUNT(*) FROM PostHistory ph20 WHERE ph20.PostId = p.Id AND ph20.PostHistoryTypeId = 50) as CommunityBumpCount,
    (SELECT COUNT(*) FROM PostHistory ph21 WHERE ph21.PostId = p.Id AND ph21.PostHistoryTypeId = 52) as SelectedHotQuestionCount,
    (SELECT COUNT(*) FROM PostHistory ph22 WHERE ph22.PostId = p.Id AND ph22.PostHistoryTypeId = 53) as RemovedHotQuestionCount,
    (SELECT COUNT(*) FROM PostHistory ph23 WHERE ph23.PostId = p.Id AND ph23.PostHistoryTypeId = 66) as CreatedFromWizardCount,
    (SELECT COUNT(*) FROM PostHistory ph24 WHERE ph24.PostId = p.Id AND ph24.PostHistoryTypeId BETWEEN 1 AND 20) as TotalEditsCount,
    (SELECT COUNT(*) FROM PostHistory ph25 WHERE ph25.PostId = p.Id AND ph25.PostHistoryTypeId IN (1, 4, 6)) as TitleBodyTagEditsCount,
    (SELECT COUNT(*) FROM PostHistory ph26 WHERE ph26.PostId = p.Id AND ph26.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25)) as ActionEditsCount,
    (SELECT COUNT(*) FROM PostHistory ph27 WHERE ph27.PostId = p.Id AND ph27.PostHistoryTypeId IN (31, 32, 33, 34, 35, 36, 37, 38, 39, 40)) as SystemEditsCount
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
WHERE p.PostTypeId IN (1, 2)
AND p.CreationDate >= '2022-01-01'
AND p.Score >= 0
AND u.Reputation > 1000
AND p.ViewCount > 100
AND p.CommentCount > 5
ORDER BY p.Score DESC, p.ViewCount DESC, p.CreationDate DESC
LIMIT 1000;