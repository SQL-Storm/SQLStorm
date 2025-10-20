SELECT 
    p.Id as PostId,
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    u.DisplayName as OwnerName,
    u.Reputation,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Tags,
    STRING_AGG(DISTINCT c.Text, ' | ') as Comments,
    STRING_AGG(DISTINCT CAST(v.VoteTypeId AS VARCHAR), ',') as VoteTypes,
    COUNT(DISTINCT ph.Id) as HistoryCount,
    STRING_AGG(DISTINCT CAST(ph.PostHistoryTypeId AS VARCHAR), ',') as HistoryTypes,
    COUNT(DISTINCT pl.Id) as LinkCount,
    STRING_AGG(DISTINCT CAST(pl.LinkTypeId AS VARCHAR), ',') as LinkTypes,
    COUNT(DISTINCT b.Id) as BadgeCount,
    STRING_AGG(DISTINCT b.Name, ',') as Badges,
    MAX(ph.CreationDate) as LastHistoryDate,
    MIN(ph.CreationDate) as FirstHistoryDate,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (10, 11, 12, 13, 14, 15, 19, 20) THEN ph.Id END) as ModerationActions,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (1, 2, 3) THEN ph.Id END) as InitialRevisions,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (4, 5, 6) THEN ph.Id END) as EditRevisions,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (7, 8, 9) THEN ph.Id END) as RollbackRevisions,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (35, 36) THEN ph.Id END) as MigrationRevisions,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (16, 33, 34) THEN ph.Id END) as SpecialActions,
    COUNT(DISTINCT CASE WHEN ph.PostHistoryTypeId IN (24, 50, 52, 53, 66) THEN ph.Id END) as SpecialRevisions,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 1 THEN p.Id END) as QuestionCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 2 THEN p.Id END) as AnswerCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 3 THEN p.Id END) as WikiCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 4 THEN p.Id END) as TagWikiExcerptCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 5 THEN p.Id END) as TagWikiCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 6 THEN p.Id END) as ModerateNominationCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 7 THEN p.Id END) as WikiPlaceholderCount,
    COUNT(DISTINCT CASE WHEN p.PostTypeId = 8 THEN p.Id END) as PrivilegeWikiCount
FROM Posts p
LEFT JOIN Users u ON p.OwnerUserId = u.Id
LEFT JOIN Comments c ON p.Id = c.PostId
LEFT JOIN Votes v ON p.Id = v.PostId
LEFT JOIN PostHistory ph ON p.Id = ph.PostId
LEFT JOIN PostLinks pl ON p.Id = pl.PostId
LEFT JOIN Badges b ON p.OwnerUserId = b.UserId
WHERE p.CreationDate BETWEEN '2010-01-01' AND '2023-12-31'
    AND p.Score >= 0
    AND p.ViewCount >= 100
GROUP BY 
    p.Id, 
    p.Title,
    p.Score,
    p.ViewCount,
    p.CreationDate,
    p.OwnerUserId,
    u.DisplayName,
    u.Reputation,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    p.Tags
HAVING 
    COUNT(DISTINCT c.Id) >= 5
    AND COUNT(DISTINCT v.Id) >= 10
    AND COUNT(DISTINCT ph.Id) >= 3
    AND COUNT(DISTINCT pl.Id) >= 2
ORDER BY 
    p.Score DESC,
    p.ViewCount DESC
LIMIT 10000;