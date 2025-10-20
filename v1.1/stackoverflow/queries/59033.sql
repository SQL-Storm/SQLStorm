SELECT 
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName as OwnerDisplayName,
    u.Reputation,
    COALESCE(c.CommentCount, 0) as CommentCount,
    COALESCE(v_up.UpVotes, 0) as UpVotes,
    COALESCE(v_down.DownVotes, 0) as DownVotes,
    COALESCE(b_g.GoldBadges, 0) as GoldBadges,
    COALESCE(b_s.SilverBadges, 0) as SilverBadges,
    COALESCE(b_b.BronzeBadges, 0) as BronzeBadges,
    t.TagsList,
    COALESCE(pq.QuestionCount, 0) as QuestionCount,
    COALESCE(pa.AnswerCount, 0) as AnswerCount,
    COALESCE(pl.DuplicateCount, 0) as DuplicateCount,
    COALESCE(ph.EditHistoryCount, 0) as EditHistoryCount,
    ph_last.LastEditDate,
    COALESCE(pp.ChildPostsCount, 0) as ChildPostsCount,
    COALESCE(pa2.AcceptedAnswersCount, 0) as AcceptedAnswersCount,
    COALESCE(v_f.FavoriteCount, 0) as FavoriteCount,
    COALESCE(ph_init_title.InitialTitleCount, 0) as InitialTitleCount,
    COALESCE(ph_init_body.InitialBodyCount, 0) as InitialBodyCount,
    COALESCE(ph_init_tags.InitialTagsCount, 0) as InitialTagsCount,
    COALESCE(ph_edit_ops.EditOperationsCount, 0) as EditOperationsCount,
    COALESCE(ph_migration.MigrationCount, 0) as MigrationCount,
    COALESCE(ph_post_migration.PostMigrationCount, 0) as PostMigrationCount,
    COALESCE(ph_post_merge.PostMergeCount, 0) as PostMergeCount,
    AVG(v_b.BountyAmount) as AvgBountyAmount,
    COALESCE(v_accept.AcceptVotesCount, 0) as AcceptVotesCount,
    COALESCE(cu.MaxCommentsPerUser, 0) as MaxCommentsPerUser
FROM Posts p
JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN (
    SELECT PostId, COUNT(*) as CommentCount
    FROM Comments
    GROUP BY PostId
) c ON c.PostId = p.Id
LEFT JOIN (
    SELECT PostId, COUNT(*) as UpVotes
    FROM Votes
    WHERE VoteTypeId = 2
    GROUP BY PostId
) v_up ON v_up.PostId = p.Id
LEFT JOIN (
    SELECT PostId, COUNT(*) as DownVotes
    FROM Votes
    WHERE VoteTypeId = 3
    GROUP BY PostId
) v_down ON v_down.PostId = p.Id
LEFT JOIN (
    SELECT UserId, COUNT(*) as GoldBadges
    FROM Badges
    WHERE Class = 1
    GROUP BY UserId
) b_g ON b_g.UserId = u.Id
LEFT JOIN (
    SELECT UserId, COUNT(*) as SilverBadges
    FROM Badges
    WHERE Class = 2
    GROUP BY UserId
) b_s ON b_s.UserId = u.Id
LEFT JOIN (
    SELECT UserId, COUNT(*) as BronzeBadges
    FROM Badges
    WHERE Class = 3
    GROUP BY UserId
) b_b ON b_b.UserId = u.Id
LEFT JOIN (
    SELECT p2.Id,
           STRING_AGG(tag, ', ') as TagsList
    FROM (
        SELECT p_inner.Id,
               UNNEST(string_to_array(SUBSTRING(p_inner.Tags FROM 2 FOR CHAR_LENGTH(p_inner.Tags)-2), '><')) as tag
        FROM Posts p_inner
    ) p_unnest
    JOIN Posts p2 ON p2.Id = p_unnest.Id
    GROUP BY p2.Id
) t ON t.Id = p.Id
LEFT JOIN (
    SELECT OwnerUserId, COUNT(*) as QuestionCount
    FROM Posts
    WHERE PostTypeId = 1
    GROUP BY OwnerUserId
) pq ON pq.OwnerUserId = u.Id
LEFT JOIN (
    SELECT OwnerUserId, COUNT(*) as AnswerCount
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY OwnerUserId
) pa ON pa.OwnerUserId = u.Id
LEFT JOIN (
    SELECT PostId, COUNT(*) as DuplicateCount
    FROM PostLinks
    WHERE LinkTypeId = 3
    GROUP BY PostId
) pl ON pl.PostId = p.Id
LEFT JOIN (
    SELECT PostId, COUNT(*) as EditHistoryCount
    FROM PostHistory
    WHERE PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20)
    GROUP BY PostId
) ph ON ph.PostId = p.Id
LEFT JOIN (
    SELECT PostId, MAX(CreationDate) as LastEditDate
    FROM PostHistory
    GROUP BY PostId
) ph_last ON ph_last.PostId = p.Id
LEFT JOIN (
    SELECT ParentId, COUNT(*) as ChildPostsCount
    FROM Posts
    GROUP BY ParentId
) pp ON pp.ParentId = p.Id
LEFT JOIN (
    SELECT AcceptedAnswerId, COUNT(*) as AcceptedAnswersCount
    FROM Posts
    WHERE AcceptedAnswerId IS NOT NULL
    GROUP BY AcceptedAnswerId
) pa2 ON pa2.AcceptedAnswerId = p.Id
LEFT JOIN (
    SELECT PostId, COUNT(*) as FavoriteCount
    FROM Votes
    WHERE VoteTypeId = 5
    GROUP BY PostId
) v_f ON v_f.PostId = p.Id
LEFT JOIN (
    SELECT PostId, COUNT(*) as InitialTitleCount
    FROM PostHistory
    WHERE PostHistoryTypeId = 1
    GROUP BY PostId
) ph_init_title ON ph_init_title.PostId = p.Id
LEFT JOIN (
    SELECT PostId, COUNT(*) as InitialBodyCount
    FROM PostHistory
    WHERE PostHistoryTypeId = 2
    GROUP BY PostId
) ph_init_body ON ph_init_body.PostId = p.Id
LEFT JOIN (
    SELECT PostId, COUNT(*) as InitialTagsCount
    FROM PostHistory
    WHERE PostHistoryTypeId = 3
    GROUP BY PostId
) ph_init_tags ON ph_init_tags.PostId = p.Id
LEFT JOIN (
    SELECT PostId, COUNT(*) as EditOperationsCount
    FROM PostHistory
    WHERE PostHistoryTypeId BETWEEN 4 AND 9
    GROUP BY PostId
) ph_edit_ops ON ph_edit_ops.PostId = p.Id
LEFT JOIN (
    SELECT PostId, COUNT(*) as MigrationCount
    FROM PostHistory
    WHERE PostHistoryTypeId IN (35, 36)
    GROUP BY PostId
) ph_migration ON ph_migration.PostId = p.Id
LEFT JOIN (
    SELECT PostId, COUNT(*) as PostMigrationCount
    FROM PostHistory
    WHERE PostHistoryTypeId IN (17, 35, 36)
    GROUP BY PostId
) ph_post_migration ON ph_post_migration.PostId = p.Id
LEFT JOIN (
    SELECT PostId, COUNT(*) as PostMergeCount
    FROM PostHistory
    WHERE PostHistoryTypeId IN (22, 37, 38)
    GROUP BY PostId
) ph_post_merge ON ph_post_merge.PostId = p.Id
LEFT JOIN (
    SELECT PostId, SUM(BountyAmount) * 0 + 0 as dummy
    FROM Votes
    WHERE VoteTypeId = 8
    GROUP BY PostId
) v_b_dummy ON v_b_dummy.PostId = p.Id
LEFT JOIN (
    SELECT PostId, BountyAmount
    FROM Votes
    WHERE VoteTypeId = 8
) v_b ON v_b.PostId = p.Id
LEFT JOIN (
    SELECT PostId, COUNT(*) as AcceptVotesCount
    FROM Votes
    WHERE VoteTypeId = 1
    GROUP BY PostId
) v_accept ON v_accept.PostId = p.Id
LEFT JOIN (
    SELECT PostId, MAX(cnt) as MaxCommentsPerUser
    FROM (
        SELECT PostId, UserId, COUNT(*) as cnt
        FROM Comments
        GROUP BY PostId, UserId
    ) x
    GROUP BY PostId
) cu ON cu.PostId = p.Id
WHERE p.PostTypeId = 1 
  AND p.CreationDate >= '2022-01-01'
  AND p.Score > 0
  AND p.ViewCount > 1000
  AND u.Reputation > 10000
  AND EXISTS (SELECT 1 FROM Badges b WHERE b.UserId = u.Id AND b.Class = 1)
  AND EXISTS (SELECT 1 FROM Votes v WHERE v.PostId = p.Id AND v.VoteTypeId = 2)
  AND EXISTS (SELECT 1 FROM PostLinks pl2 WHERE pl2.PostId = p.Id AND pl2.LinkTypeId = 3)
  AND EXISTS (SELECT 1 FROM PostHistory ph2 WHERE ph2.PostId = p.Id AND ph2.PostHistoryTypeId IN (10, 11, 12, 13))
  AND NOT EXISTS (SELECT 1 FROM Posts p6 WHERE p6.ParentId = p.Id AND p6.PostTypeId = 2 AND p6.Score < 0)
  AND NOT EXISTS (SELECT 1 FROM Tags t2 WHERE t2.TagName LIKE '%performance%' OR t2.TagName LIKE '%benchmark%')
GROUP BY p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, u.DisplayName, u.Reputation,
         c.CommentCount, v_up.UpVotes, v_down.DownVotes, b_g.GoldBadges, b_s.SilverBadges, b_b.BronzeBadges,
         t.TagsList, pq.QuestionCount, pa.AnswerCount, pl.DuplicateCount, ph.EditHistoryCount, ph_last.LastEditDate,
         pp.ChildPostsCount, pa2.AcceptedAnswersCount, v_f.FavoriteCount, ph_init_title.InitialTitleCount,
         ph_init_body.InitialBodyCount, ph_init_tags.InitialTagsCount, ph_edit_ops.EditOperationsCount,
         ph_migration.MigrationCount, ph_post_migration.PostMigrationCount, ph_post_merge.PostMergeCount,
         v_accept.AcceptVotesCount, cu.MaxCommentsPerUser, u.Id
HAVING COUNT(DISTINCT u.Id) = 1
ORDER BY p.Score DESC, p.ViewCount DESC
LIMIT 1000;