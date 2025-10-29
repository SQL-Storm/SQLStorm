-- {"query": "2512.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1429}
with RecursiveUserActivity as (
    select u.Id as UserId,
           u.DisplayName,
           u.Reputation,
           u.CreationDate,
           u.Location,
           count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsCount,
           count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersCount,
           count(distinct b.Id) as BadgeCount,
           max(p.CreationDate) as LastPostDate
      from Users u
      left join Posts p on p.OwnerUserId = u.Id
      left join Badges b on b.UserId = u.Id
     where u.Reputation > 1000
     group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
),
UserRankings as (
    select rua.*,
           row_number() over (order by rua.Reputation desc, rua.LastPostDate desc) as ReputationRank,
           dense_rank() over (partition by rua.Location order by rua.Reputation desc) as LocationReputationRank
      from RecursiveUserActivity rua
),
FilteredPosts as (
    select p.Id,
           p.PostTypeId,
           p.AcceptedAnswerId,
           p.ParentId,
           p.CreationDate,
           p.Score,
           p.ViewCount,
           p.Body,
           p.OwnerUserId,
           p.OwnerDisplayName,
           p.LastEditorUserId,
           p.LastEditorDisplayName,
           p.LastEditDate,
           p.LastActivityDate,
           p.Title,
           p.Tags,
           p.AnswerCount,
           p.CommentCount,
           p.FavoriteCount,
           p.ClosedDate,
           p.CommunityOwnedDate,
           p.ContentLicense,
           substring(coalesce(p.Title, '') from 1 for 100) as TitleSnippet,
           char_length(coalesce(p.Body, '')) as BodyLength,
           case when p.Tags is not null then array_length(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><'), 1) else 0 end as TagCount
      from Posts p
     where p.PostTypeId in (1, 2)
       and p.Score >= 5
       and (p.ClosedDate is null or p.ClosedDate > (timestamp '2024-10-01 12:34:56' - interval '1 year'))
),
PostWithDuplicates as (
    select fp.Id,
           fp.PostTypeId,
           fp.AcceptedAnswerId,
           fp.ParentId,
           fp.CreationDate,
           fp.Score,
           fp.ViewCount,
           fp.Body,
           fp.OwnerUserId,
           fp.OwnerDisplayName,
           fp.LastEditorUserId,
           fp.LastEditorDisplayName,
           fp.LastEditDate,
           fp.LastActivityDate,
           fp.Title,
           fp.Tags,
           fp.AnswerCount,
           fp.CommentCount,
           fp.FavoriteCount,
           fp.ClosedDate,
           fp.CommunityOwnedDate,
           fp.ContentLicense,
           fp.TitleSnippet,
           fp.BodyLength,
           fp.TagCount,
           count(distinct pl.Id) filter (where lt.Name = 'Duplicate') as DuplicateLinksCount
      from FilteredPosts fp
      left join PostLinks pl on pl.PostId = fp.Id
      left join LinkTypes lt on lt.Id = pl.LinkTypeId
     group by fp.Id, fp.PostTypeId, fp.AcceptedAnswerId, fp.ParentId, fp.CreationDate, fp.Score, fp.ViewCount, fp.Body, fp.OwnerUserId, fp.OwnerDisplayName,
              fp.LastEditorUserId, fp.LastEditorDisplayName, fp.LastEditDate, fp.LastActivityDate, fp.Title, fp.Tags, fp.AnswerCount, fp.CommentCount,
              fp.FavoriteCount, fp.ClosedDate, fp.CommunityOwnedDate, fp.ContentLicense, fp.TitleSnippet, fp.BodyLength, fp.TagCount
),
DetailedPostHistory as (
    select ph.PostId,
           ph.PostHistoryTypeId,
           pht.Name as HistoryTypeName,
           ph.UserId,
           u.DisplayName as EditorDisplayName,
           ph.CreationDate,
           ph.Comment,
           ph.Text,
           row_number() over (partition by ph.PostId order by ph.CreationDate desc) as HistorySeqDesc
      from PostHistory ph
      join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId
      left join Users u on u.Id = ph.UserId
     where ph.PostHistoryTypeId in (4, 5, 6, 10, 11)
),
TopPostHistories as (
    select distinct on (dph.PostId) dph.PostId,
           dph.HistoryTypeName,
           dph.EditorDisplayName,
           dph.CreationDate as LastEditDate,
           dph.Comment
      from DetailedPostHistory dph
     order by dph.PostId, dph.CreationDate desc
),
AnswersWithRanks as (
    select p.Id,
           p.ParentId,
           p.PostTypeId,
           p.Score,
           p.CreationDate,
           row_number() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank,
           rank() over (partition by p.ParentId order by p.Score desc) as AnswerScoreRank
      from Posts p
     where p.PostTypeId = 2
)
select u.UserId,
       u.DisplayName,
       u.Reputation,
       u.Location,
       u.QuestionsCount,
       u.AnswersCount,
       u.BadgeCount,
       u.LastPostDate,
       u.ReputationRank,
       u.LocationReputationRank,
       p.Id as PostId,
       p.PostTypeId,
       pw.TitleSnippet,
       p.Score,
       p.ViewCount,
       pw.TagCount,
       pw.DuplicateLinksCount,
       tph.HistoryTypeName as LastPostHistoryType,
       tph.EditorDisplayName as LastEditor,
       tph.LastEditDate,
       tph.Comment as LastEditComment,
       a.Id as TopAnswerId,
       a.Score as TopAnswerScore,
       a.AnswerRank,
       a.AnswerScoreRank,
       case 
         when p.Title is null or char_length(trim(both from p.Title)) = 0 then 'Untitled' 
         else upper(substring(p.Title from 1 for 1)) || substring(p.Title from 2)
       end as TitleCapitalized,
       case when position('sql' in lower(coalesce(p.Body, ''))) > 0 then true else false end as ContainsSQL
  from UserRankings u
  join Posts p on p.OwnerUserId = u.UserId
  left join PostWithDuplicates pw on pw.Id = p.Id
  left join TopPostHistories tph on tph.PostId = p.Id
  left join AnswersWithRanks a on a.ParentId = p.Id and a.AnswerRank = 1
 where p.PostTypeId = 1
   and u.QuestionsCount > 5
   and (a.Score is null or a.Score > 0)
union
select u.UserId,
       u.DisplayName,
       u.Reputation,
       u.Location,
       u.QuestionsCount,
       u.AnswersCount,
       u.BadgeCount,
       u.LastPostDate,
       upr.ReputationRank,
       upr.LocationReputationRank,
       c.PostId,
       p.PostTypeId,
       null as TitleSnippet,
       p.Score,
       p.ViewCount,
       0 as TagCount,
       0 as DuplicateLinksCount,
       null as LastPostHistoryType,
       null as LastEditor,
       null as LastEditDate,
       null as LastEditComment,
       null as TopAnswerId,
       null as TopAnswerScore,
       null as AnswerRank,
       null as AnswerScoreRank,
       null as TitleCapitalized,
       null as ContainsSQL
  from UserRankings u
  join Comments c on c.UserId = u.UserId
  join Posts p on p.Id = c.PostId
  left join UserRankings upr on upr.UserId = u.UserId
 where p.PostTypeId = 1
   and c.Score > 10
order by ReputationRank, LastPostDate desc, PostId
limit 100;