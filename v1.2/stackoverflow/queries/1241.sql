-- {"query": "1241.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1547} 
with RankedPosts as (
  select
    p.Id,
    p.PostTypeId,
    p.AcceptedAnswerId,
    p.ParentId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    p.OwnerUserId,
    p.Title,
    p.AnswerCount,
    p.CommentCount,
    p.FavoriteCount,
    row_number() over(partition by p.PostTypeId order by p.Score desc, p.ViewCount desc nulls last) as rn
  from Posts p
  where p.PostTypeId in (1,2)
    and (p.Score is not null and p.ViewCount is not null)
    and p.CreationDate >= '2020-01-01'
),
QuestionAnswers as (
  select
    q.Id as QuestionId,
    q.Title,
    q.Score as QuestionScore,
    q.ViewCount as QuestionViews,
    a.Id as AnswerId,
    a.Score as AnswerScore,
    a.CreationDate as AnswerCreationDate,
    a.OwnerUserId as AnswerOwnerUserId,
    dense_rank() over(partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
  from RankedPosts q
  left join RankedPosts a on a.PostTypeId = 2 and a.ParentId = q.Id
  where q.rn <= 100
),
AnswerVotes as (
  select
    v.PostId,
    count(case when vt.Name = 'UpMod' then 1 end) as UpVotes,
    count(case when vt.Name = 'DownMod' then 1 end) as DownVotes,
    count(case when vt.Name = 'Spam' or vt.Name = 'Offensive' then 1 end) as Flags
  from Votes v
  join VoteTypes vt on vt.Id = v.VoteTypeId
  where v.PostId in (select AnswerId from QuestionAnswers)
  group by v.PostId
), 
UserStatistics as (
  select
    u.Id,
    u.DisplayName,
    u.Reputation,
    u.Location,
    coalesce(u.Views,0) as Views,
    coalesce(u.UpVotes,0) as UpVotes,
    coalesce(u.DownVotes,0) as DownVotes,
    count(distinct b.Id) filter (where b.Class = 1) as GoldBadges,
    count(distinct b.Id) filter (where b.Class = 2) as SilverBadges,
    count(distinct b.Id) filter (where b.Class = 3) as BronzeBadges,
    dense_rank() over(order by u.Reputation desc, u.Views desc) as ReputationRank
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation, u.Location, u.Views, u.UpVotes, u.DownVotes
),
AnswerDetails as (
  select
    qa.QuestionId,
    qa.Title,
    qa.QuestionScore,
    qa.QuestionViews,
    qa.AnswerId,
    qa.AnswerScore,
    qa.AnswerCreationDate,
    qa.AnswerOwnerUserId,
    au.DisplayName as AnswerOwnerDisplayName,
    av.UpVotes,
    av.DownVotes,
    av.Flags,
    us.Reputation as AnswerUserReputation,
    us.GoldBadges,
    us.SilverBadges,
    us.BronzeBadges,
    us.Location as AnswerUserLocation,
    rank() over(partition by qa.QuestionId order by av.UpVotes - av.DownVotes desc nulls last, qa.AnswerScore desc nulls last) as VoteRank
  from QuestionAnswers qa
  left join AnswerVotes av on av.PostId = qa.AnswerId
  left join Users au on au.Id = qa.AnswerOwnerUserId
  left join UserStatistics us on us.Id = qa.AnswerOwnerUserId
  where qa.AnswerId is not null
),
QuestionSummary as (
  select
    q.Id,
    q.Title,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.CommentCount,
    q.FavoriteCount,
    q.Tags,
    case 
      when q.AcceptedAnswerId is null then 'No Accepted Answer'
      else 'Has Accepted Answer'
    end as AcceptedStatus,
    (select count(*) from Comments c where c.PostId = q.Id and c.CreationDate > q.CreationDate) as NewCommentsAfterCreation
  from Posts q
  where q.PostTypeId = 1
    and q.CreationDate > cast('2024-10-01' as date) - interval '365 days'
),
DuplicateQuestions as (
  select distinct
    ql.PostId as DuplicateQuestionId,
    ql.RelatedPostId as OriginalQuestionId,
    q.Title as DuplicateTitle,
    og.Title as OriginalTitle,
    l.Name as LinkTypeName
  from PostLinks ql
  join LinkTypes l on l.Id = ql.LinkTypeId and l.Name = 'Duplicate'
  join Posts q on q.Id = ql.PostId
  join Posts og on og.Id = ql.RelatedPostId
  where q.PostTypeId = 1 and og.PostTypeId = 1
),
CTE_BadgedUsers as (
  select distinct UserId from Badges where Class = 1
),
CTE_UserBestAnswer as (
  select distinct on (OwnerUserId) 
    OwnerUserId,
    Id as AnswerId,
    Score,
    CreationDate
  from Posts
  where PostTypeId = 2
  order by OwnerUserId, Score desc, CreationDate asc
)
select 
  qs.Id as QuestionId,
  qs.Title,
  qs.Score as QuestionScore,
  qs.ViewCount as QuestionViews,
  qs.AcceptedStatus,
  qs.NewCommentsAfterCreation,
  ad.AnswerId,
  ad.AnswerScore,
  ad.UpVotes,
  ad.DownVotes,
  ad.Flags,
  ad.AnswerOwnerUserId,
  ad.AnswerOwnerDisplayName,
  ad.AnswerUserReputation,
  ad.GoldBadges,
  ad.SilverBadges,
  ad.BronzeBadges,
  ad.AnswerUserLocation,
  ad.VoteRank,
  dq.DuplicateQuestionId,
  dq.OriginalQuestionId,
  dq.DuplicateTitle,
  dq.OriginalTitle,
  dq.LinkTypeName,
  ub.UserId as GoldBadgedUserId,
  uba.AnswerId as UserBestAnswerId,
  ubg.MaxScore as MaxUserScore
from QuestionSummary qs
left join AnswerDetails ad on ad.QuestionId = qs.Id and ad.VoteRank = 1
left join DuplicateQuestions dq on dq.DuplicateQuestionId = qs.Id
left join CTE_BadgedUsers ub on ub.UserId = ad.AnswerOwnerUserId
left join CTE_UserBestAnswer uba on uba.OwnerUserId = ad.AnswerOwnerUserId
left join (
  select OwnerUserId, max(Score) as MaxScore from Posts where PostTypeId = 2 group by OwnerUserId
) ubg on ubg.OwnerUserId = ad.AnswerOwnerUserId
where (qs.Score > 10 or qs.ViewCount > 1000)
order by qs.Score desc nulls last, ad.UpVotes desc nulls last, qs.NewCommentsAfterCreation desc nulls last
limit 100;