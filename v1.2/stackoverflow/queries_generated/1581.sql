-- {"query": "1581.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1073} 
with RankedPosts as (
  select
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.Score,
    p.FavoriteCount,
    p.Tags,
    p.Title,
    p.CreationDate,
    u.DisplayName as OwnerName,
    u.Reputation as OwnerRep,
    row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last, p.CreationDate desc) as rn
  from Posts p
  left join Users u on p.OwnerUserId = u.Id
  where p.PostTypeId in (1, 2) -- Questions and Answers
),
CloseReasonsCount as (
  select ph.PostId, crt.Name as CloseReasonName, count(*) as CloseReasonVotes
  from PostHistory ph
  join CloseReasonTypes crt on cast(ph.Comment as int) = crt.Id and ph.PostHistoryTypeId = 10
  group by ph.PostId, crt.Name
),
TopQuestions as (
  select rp.Id, rp.Title, rp.OwnerUserId, rp.OwnerName, rp.OwnerRep, rp.Score, 
         array_agg(distinct split_part(trim(both '><' from unnest(string_to_array(rp.Tags, '><'))), ' ', 1)) filter (where rp.Tags is not null) as TagList
  from RankedPosts rp
  where rp.PostTypeId = 1 and rn <= 10
  group by rp.Id, rp.Title, rp.OwnerUserId, rp.OwnerName, rp.OwnerRep, rp.Score
),
AnswersByTopQuestions as (
  select p.ParentId as QuestionId, count(p.Id) as AnswersCount,
         avg(p.Score) as AvgAnswerScore,
         max(p.Score) as MaxAnswerScore,
         count(case when p.CreationDate > (select CreationDate from Posts where Id = p.ParentId) + interval '7 days' then 1 end) as AnswersAfterWeek
  from Posts p
  where p.PostTypeId = 2
  group by p.ParentId
),
UserEngagement as (
  select u.Id, u.DisplayName, u.Reputation,
         count(distinct b.Id) as BadgeCount,
         count(distinct c.Id) as CommentCount,
         sum(coalesce(vs.UpVotes,0)) as TotalUpVotes,
         sum(coalesce(vs.DownVotes,0)) as TotalDownVotes,
         row_number() over(order by u.Reputation desc) as UserRank
  from Users u
  left join Badges b on b.UserId = u.Id
  left join Comments c on c.UserId = u.Id
  left join (
    select PostId, 
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
    from Votes v
    join VoteTypes vt on v.VoteTypeId = vt.Id
    group by PostId
  ) vs on vs.PostId in (select Id from Posts where OwnerUserId = u.Id)
  group by u.Id, u.DisplayName, u.Reputation
)
select 
  tq.Title,
  tq.Id as QuestionId,
  coalesce(crc.CloseReasonVotes, 0) as CloseVotes,
  crc.CloseReasonName,
  tq.OwnerName,
  tq.OwnerRep,
  array_to_string(tq.TagList, ', ') as Tags,
  coalesce(abt.AnswersCount,0) as AnswersCount,
  coalesce(abt.AvgAnswerScore,0)::numeric(5,2) as AvgAnswerScore,
  coalesce(abt.MaxAnswerScore,0) as MaxAnswerScore,
  coalesce(abt.AnswersAfterWeek,0) as AnswersPostedAfterOneWeek
from TopQuestions tq
left join CloseReasonsCount crc on tq.Id = crc.PostId
left join AnswersByTopQuestions abt on tq.Id = abt.QuestionId
where exists (
  select 1 from UserEngagement ue
  where ue.Id = tq.OwnerUserId 
    and ( ue.Reputation > 5000 
          or ue.BadgeCount >= 10
          or ue.CommentCount > sum(transform(\  
            select varchar from regexp_split_to_table(tq.TagList::varchar,'[,:|]')::varchar))) -- Complicated expression involving string array Dyn Condition
)
union 
select
  'Unowned' as Title,
  p.Id as QuestionId,
  0 as CloseVotes,
  NULL as CloseReasonName,
  NULL as OwnerName,
  0 as OwnerRep,
  NULL as Tags,
  0 as AnswersCount,
  0 as AvgAnswerScore,
  0 as MaxAnswerScore,
  0 as AnswersPostedAfterOneWeek
from Posts p
left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
where p.PostTypeId = 1 
  and p.OwnerUserId is null
  and a.Id is null
order by OwnerRep desc nulls last, AnswersCount desc, CloseVotes desc;