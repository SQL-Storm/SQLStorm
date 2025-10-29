-- {"query": "2190.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1379}
with RecursiveBadges as (
  select b.Id, b.UserId, b.Name, b.Class, b.Date,
    row_number() over (partition by b.UserId order by b.Date) as BadgeRank
  from Badges b
  where b.Class in (1,2)
),
UserActivity as (
  select
    u.Id as UserId,
    u.DisplayName,
    count(case when p.PostTypeId = 1 then 1 end) as QuestionCount,
    count(case when p.PostTypeId = 2 then 1 end) as AnswerCount,
    coalesce(sum(p.Score),0) as TotalPostScore,
    max(p.CreationDate) as LastPostDate,
    max(coalesce(v.UpVotes,0)) as MaxUpVotes,
    min(coalesce(v.DownVotes,0)) as MinDownVotes
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Users v on v.Id = u.Id
  group by u.Id, u.DisplayName
),
PostWithCloseReason as (
  select 
    p.Id,
    p.Title,
    p.PostTypeId,
    p.CreationDate,
    p.Score,
    p.ViewCount,
    p.Tags,
    crt.Name as CloseReasonName,
    (select ph.Comment 
     from PostHistory ph 
     where ph.PostId = p.Id 
       and ph.PostHistoryTypeId = 10 
     order by ph.CreationDate desc limit 1
    ) as CloseReasonDetail
  from Posts p
  left join PostHistory ph_close on ph_close.PostId = p.Id and ph_close.PostHistoryTypeId = 10
  left join CloseReasonTypes crt on crt.Id = CAST(ph_close.Comment AS integer)
),
TopTags as (
  select 
    t.Id, t.TagName,
    t.Count,
    row_number() over (order by t.Count desc) as RankByCount
  from Tags t
  where t.TagName is not null
),
QuestionsWithAnswers as (
  select 
    q.Id as QuestionId,
    q.Title,
    q.CreationDate as QuestionDate,
    a.Id as AnswerId,
    a.CreationDate as AnswerDate,
    a.Score as AnswerScore,
    u.DisplayName as Answerer,
    rank() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
  from Posts q
  left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
  left join Users u on u.Id = a.OwnerUserId
  where q.PostTypeId = 1
),
DuplicateQuestions as (
  select pl.PostId, pl.RelatedPostId
  from PostLinks pl
  join LinkTypes lt on lt.Id = pl.LinkTypeId
  where lt.Name = 'Duplicate'
),
CorrelatedVoteSummary as (
  select
    p.Id as PostId,
    count(case when vt.Name = 'UpMod' then 1 end) as UpVotes,
    count(case when vt.Name = 'DownMod' then 1 end) as DownVotes,
    coalesce(sum(v.BountyAmount),0) as TotalBounty
  from Posts p
  left join Votes v on v.PostId = p.Id
  left join VoteTypes vt on vt.Id = v.VoteTypeId
  group by p.Id
),
RecentUserEngagement as (
  select 
    u.Id as UserId,
    u.DisplayName,
    max(p.CreationDate) as LastPost,
    max(c.CreationDate) as LastComment
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Comments c on c.UserId = u.Id
  group by u.Id, u.DisplayName
)
select distinct
  ua.UserId,
  ua.DisplayName,
  ua.QuestionCount,
  ua.AnswerCount,
  ua.TotalPostScore,
  rb.Name as LatestGoldBadge,
  pwr.CloseReasonName,
  pwr.CloseReasonDetail,
  tq_main.Title as TopQuestionTitle,
  tq_qa.AnswerScore,
  tq_qa.Answerer,
  ts.TagName as TopTag,
  ds.RelatedPostId as DuplicateForPost,
  cvs.UpVotes,
  cvs.DownVotes,
  cvs.TotalBounty,
  rue.LastPost,
  rue.LastComment,
  case 
    when ua.MaxUpVotes is null then 'No upvotes'
    when ua.MaxUpVotes > 100 then 'High UpVotes'
    else 'Moderate UpVotes'
  end as UpVoteCategory,
  case when ua.MinDownVotes is null then 'No downvotes' else 'Some downvotes' end as DownVotePresence
from UserActivity ua
left join RecursiveBadges rb on rb.UserId = ua.UserId and rb.BadgeRank = 1 and rb.Class = 1
left join Posts tq_main on tq_main.OwnerUserId = ua.UserId and tq_main.PostTypeId = 1
left join QuestionsWithAnswers tq_qa on tq_qa.QuestionId = tq_main.Id and tq_qa.AnswerRank = 1
left join PostWithCloseReason pwr on pwr.Id = tq_main.Id
left join TopTags ts on ts.RankByCount = 1
left join DuplicateQuestions ds on ds.PostId = tq_main.Id
left join CorrelatedVoteSummary cvs on cvs.PostId = tq_main.Id
left join RecentUserEngagement rue on rue.UserId = ua.UserId
where ua.QuestionCount > 5
  and ua.TotalPostScore > 50
  and (pwr.CloseReasonName is null or pwr.CloseReasonName = 'Off-topic')
union
select 
  u.Id as UserId,
  u.DisplayName,
  0 as QuestionCount,
  0 as AnswerCount,
  0 as TotalPostScore,
  null as LatestGoldBadge,
  null as CloseReasonName,
  null as CloseReasonDetail,
  null as TopQuestionTitle,
  null as AnswerScore,
  null as Answerer,
  null as TopTag,
  null as DuplicateForPost,
  0 as UpVotes,
  0 as DownVotes,
  0 as TotalBounty,
  null as LastPost,
  null as LastComment,
  'Inactive' as UpVoteCategory,
  'No downvotes' as DownVotePresence
from Users u
where not exists (select 1 from Posts p where p.OwnerUserId = u.Id)
order by UserId
limit 100;