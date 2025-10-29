-- {"query": "2167.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1161} 
with RecursiveUserBadges as (
    select u.Id as UserId,
           u.DisplayName,
           u.Reputation,
           b.Name as BadgeName,
           b.Class,
           b.Date as BadgeDate,
           row_number() over (partition by u.Id order by b.Date desc) as BadgeRank
      from Users u
      left join Badges b on u.Id = b.UserId
     where u.Reputation > 1000
), 
TopUserBadges as (
    select UserId,
           DisplayName,
           Reputation,
           BadgeName,
           Class,
           BadgeDate
      from RecursiveUserBadges
     where BadgeRank <= 3
),
UserQuestionAnswers as (
    select u.Id as UserId,
           u.DisplayName,
           q.Id as QuestionId,
           q.Title,
           q.Score as QuestionScore,
           a.Id as AnswerId,
           a.Score as AnswerScore,
           a.CreationDate as AnswerCreationDate,
           row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
      from Users u
      join Posts q on q.OwnerUserId = u.Id and q.PostTypeId = 1
      left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
     where u.Reputation >= 5000
),
HighlyVotedAcceptedAnswers as (
    select q.UserId,
           count(*) as AcceptedAnswerCount,
           avg(q.AnswerScore) as AvgAcceptedAnswerScore 
      from UserQuestionAnswers q
     where q.AnswerId = (select p.AcceptedAnswerId from Posts p where p.Id = q.QuestionId)
       and q.AnswerScore > 10
     group by q.UserId
),
LatestPostComments as (
    select c.PostId,
           max(c.CreationDate) as LastCommentDate,
           count(c.Id) as CommentCount
      from Comments c
     group by c.PostId
),
PostLinkSummary as (
    select pl.PostId,
           sum(case when lt.Name = 'Duplicate' then 1 else 0 end) as DuplicateLinks,
           sum(case when lt.Name = 'Linked' then 1 else 0 end) as LinkedLinks
      from PostLinks pl
      join LinkTypes lt on pl.LinkTypeId = lt.Id
     group by pl.PostId
),
FinalSelectedPosts as (
    select p.Id,
           p.Title,
           p.CreationDate,
           p.Score,
           p.ViewCount,
           p.Tags,
           u.DisplayName as OwnerName,
           u.Reputation as OwnerReputation,
           hvt.Name as PostHistoryTypeName,
           ph.CreationDate as PostHistoryDate,
           ph.Comment as PostHistoryComment,
           lsc.LastCommentDate,
           lsc.CommentCount,
           pls.DuplicateLinks,
           pls.LinkedLinks,
           row_number() over (partition by p.Id order by ph.CreationDate desc) as HistoryRank
      from Posts p
      left join Users u on p.OwnerUserId = u.Id
      left join PostHistory ph on ph.PostId = p.Id
      left join PostHistoryTypes hvt on ph.PostHistoryTypeId = hvt.Id
      left join LatestPostComments lsc on lsc.PostId = p.Id
      left join PostLinkSummary pls on pls.PostId = p.Id
     where p.Score >= 5
       and (p.Tags is not null and position('sql' in lower(p.Tags)) > 0)
)
select fsp.Id,
       fsp.Title,
       fsp.CreationDate,
       fsp.Score,
       fsp.ViewCount,
       coalesce(nullif(fsp.Tags, ''), '<no tags>') as NormalizedTags,
       fsp.OwnerName,
       fsp.OwnerReputation,
       string_agg(distinct tou.BadgeName || 
                  case tou.Class 
                      when 1 then ' (Gold)' 
                      when 2 then ' (Silver)' 
                      when 3 then ' (Bronze)' 
                      else '' end, ', ') as TopBadges,
       fsp.PostHistoryTypeName,
       fsp.PostHistoryDate,
       fsp.PostHistoryComment,
       fsp.LastCommentDate,
       fsp.CommentCount,
       fsp.DuplicateLinks,
       fsp.LinkedLinks,
       hva.AcceptedAnswerCount,
       round(hva.AvgAcceptedAnswerScore, 2) as AvgAcceptedAnswerScore
  from FinalSelectedPosts fsp
  left join TopUserBadges tou on tou.UserId = (select distinct OwnerUserId from Posts where Id = fsp.Id limit 1)
  left join HighlyVotedAcceptedAnswers hva on hva.UserId = (select distinct OwnerUserId from Posts where Id = fsp.Id limit 1)
 where fsp.HistoryRank = 1
 group by fsp.Id, fsp.Title, fsp.CreationDate, fsp.Score, fsp.ViewCount, fsp.Tags, fsp.OwnerName, fsp.OwnerReputation, 
          fsp.PostHistoryTypeName, fsp.PostHistoryDate, fsp.PostHistoryComment, fsp.LastCommentDate, fsp.CommentCount, 
          fsp.DuplicateLinks, fsp.LinkedLinks, hva.AcceptedAnswerCount, hva.AvgAcceptedAnswerScore
 having (fsp.CommentCount > 10 or fsp.DuplicateLinks > 0)
 order by fsp.Score desc, fsp.ViewCount desc, fsp.CreationDate asc
 limit 100;