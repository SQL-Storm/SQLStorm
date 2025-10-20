SELECT 
    p.Id AS PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    u.DisplayName AS OwnerDisplayName,
    u.Reputation,
    COUNT(DISTINCT c.Id) AS CommentCount,
    COUNT(DISTINCT v.Id) AS VoteCount,
    COUNT(DISTINCT bh.Id) AS HistoryCount,
    COUNT(DISTINCT pl.Id) AS LinkCount,
    STRING_AGG(DISTINCT t.TagName, ', ') AS Tags,
    CASE 
        WHEN p.PostTypeId = 1 THEN 'Question'
        WHEN p.PostTypeId = 2 THEN 'Answer'
        WHEN p.PostTypeId = 3 THEN 'Wiki'
        WHEN p.PostTypeId = 4 THEN 'TagWikiExcerpt'
        WHEN p.PostTypeId = 5 THEN 'TagWiki'
        WHEN p.PostTypeId = 6 THEN 'ModeratorNomination'
        WHEN p.PostTypeId = 7 THEN 'WikiPlaceholder'
        WHEN p.PostTypeId = 8 THEN 'PrivilegeWiki'
    END AS PostTypeName,
    CASE 
        WHEN p.ClosedDate IS NOT NULL THEN 'Closed'
        WHEN p.CommunityOwnedDate IS NOT NULL THEN 'Community Owned'
        WHEN p.ParentId IS NOT NULL THEN 'Answer'
        ELSE 'Question'
    END AS PostStatus,
    COALESCE(p.AnswerCount, 0) AS AnswerCount,
    COALESCE(p.FavoriteCount, 0) AS FavoriteCount,
    MAX(v.CreationDate) AS LastVoteDate,
    MAX(c.CreationDate) AS LastCommentDate,
    MAX(bh.CreationDate) AS LastHistoryDate,
    MIN(pl.CreationDate) AS FirstLinkDate,
    STRING_AGG(DISTINCT CAST(b.Id AS VARCHAR), ', ') AS BadgeIds,
    STRING_AGG(DISTINCT b.Name, ', ') AS BadgeNames,
    STRING_AGG(DISTINCT CAST(b.Class AS VARCHAR), ', ') AS BadgeClasses,
    COUNT(DISTINCT CASE WHEN b.Class = 1 THEN b.Id END) AS GoldBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 2 THEN b.Id END) AS SilverBadges,
    COUNT(DISTINCT CASE WHEN b.Class = 3 THEN b.Id END) AS BronzeBadges,
    COALESCE(uq.UserQuestionCount, 0) AS UserQuestionCount,
    COALESCE(ua.UserAnswerCount, 0) AS UserAnswerCount,
    COALESCE(uqhs.UserHighScoreQuestions, 0) AS UserHighScoreQuestions,
    COALESCE(uahs.UserHighScoreAnswers, 0) AS UserHighScoreAnswers,
    STRING_AGG(DISTINCT ph.Text, ' | ') AS HistoryTexts,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (1, 4, 6) THEN ph.Id END) AS TitleBodyTagEdits,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13) THEN ph.Id END) AS StatusChanges,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (24) THEN ph.Id END) AS EditApplications
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory bh ON p.Id = bh.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN (
    SELECT posts_with_tags.Id AS PostId, tags.TagName 
    FROM Posts posts_with_tags
    JOIN (
        SELECT Id, UNNEST(string_to_array(TRIM(BOTH '<' FROM TRIM(BOTH '>' FROM Tags)) , '><')) AS TagName
        FROM Posts
        WHERE Tags IS NOT NULL AND Tags <> ''
    ) tags ON posts_with_tags.Id = tags.Id
) t ON p.Id = t.PostId
LEFT JOIN Badges b ON p.OwnerUserId = b.UserId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN (
    SELECT OwnerUserId, COUNT(*) AS UserQuestionCount
    FROM Posts
    WHERE PostTypeId = 1
    GROUP BY OwnerUserId
) uq ON uq.OwnerUserId = p.OwnerUserId
LEFT JOIN (
    SELECT OwnerUserId, COUNT(*) AS UserAnswerCount
    FROM Posts
    WHERE PostTypeId = 2
    GROUP BY OwnerUserId
) ua ON ua.OwnerUserId = p.OwnerUserId
LEFT JOIN (
    SELECT OwnerUserId, COUNT(*) AS UserHighScoreQuestions
    FROM Posts
    WHERE PostTypeId = 1 AND Score > 0
    GROUP BY OwnerUserId
) uqhs ON uqhs.OwnerUserId = p.OwnerUserId
LEFT JOIN (
    SELECT OwnerUserId, COUNT(*) AS UserHighScoreAnswers
    FROM Posts
    WHERE PostTypeId = 2 AND Score > 0
    GROUP BY OwnerUserId
) uahs ON uahs.OwnerUserId = p.OwnerUserId
WHERE p.CreationDate >= '2020-01-01'
    AND p.CreationDate < '2024-01-01'
    AND p.PostTypeId IN (1, 2)
    AND p.ViewCount > 100
GROUP BY 
    p.Id, 
    p.Title, 
    p.Score, 
    p.ViewCount, 
    p.CreationDate, 
    u.DisplayName, 
    u.Reputation, 
    p.PostTypeId, 
    p.ClosedDate, 
    p.CommunityOwnedDate, 
    p.ParentId, 
    p.AnswerCount, 
    p.FavoriteCount,
    uq.UserQuestionCount,
    ua.UserAnswerCount,
    uqhs.UserHighScoreQuestions,
    uahs.UserHighScoreAnswers
HAVING 
    COUNT(DISTINCT c.Id) > 5
    AND COUNT(DISTINCT v.Id) > 10
    AND COUNT(DISTINCT bh.Id) > 2
    AND COUNT(DISTINCT pl.Id) > 0
ORDER BY 
    p.Score DESC,
    p.ViewCount DESC,
    p.CreationDate DESC
LIMIT 1000;