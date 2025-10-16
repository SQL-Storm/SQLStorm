-- {"query": "1471.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1560} 
with recursive UserActivity AS (
  select 
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.CreationDate,
    case when p.Id is null then 0 else 1 end as HasPosts,
    row_number() over (partition by u.Id order by p.CreationDate desc nulls last) as rn
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
),
TopUserPosts as (
  select distinct
    p.Id as PostId,
    p.OwnerUserId,
    p.PostTypeId,
    p.Score,
    p.CreationDate,
    p.AcceptedAnswerId,
    p.Tags,
    coalesce(pc.CommentCount,0) as NumComments,
    rank() over (partition by p.OwnerUserId order by p.Score desc, p.CreationDate desc) as OwnerPostRank
  from Posts p
  left join (
    select PostId, count(*) as CommentCount
    from Comments
    group by PostId
  ) pc on pc.PostId = p.Id
  where p.PostTypeId in (1, 2) -- questions and answers
),
AnswersRanked AS (
  select
    a.Id as AnswerId,
    a.ParentId as QuestionId,
    a.OwnerUserId,
    a.Score,
    dense_rank() over (partition by a.ParentId order by a.Score desc) as AnswerRank
  from Posts a
  where a.PostTypeId = 2
),
AggregatedVotes AS (
  select 
    v.PostId,
    count(case when v.VoteTypeId = 2 then 1 end) as UpVotes,
    count(case when v.VoteTypeId = 3 then 1 end) as DownVotes,
    count(case when v.VoteTypeId = 6 then 1 end) as CloseVotes,
    count(case when v.VoteTypeId not in (2, 3, 6) then 1 end) as OtherVotes
  from Votes v
  group by v.PostId
),
FilteredCloseReasons AS (
  select
    hist.PostId,
    crt.Name as CloseReason,
    max(hist.CreationDate) as LastCloseDate
  from PostHistory hist 
  join CloseReasonTypes crt on crt.Id::int = cast(hist.Comment as int)
  where hist.PostHistoryTypeId = 10
    and crt.Id in (101, 102, 103, 104, 105) -- current close reasons only
  group by hist.PostId, crt.Name
),
SearchCanonicalTags AS (
  select 
    t.Id,
    t.TagName,
    length(t.TagName) as TagLength,
    coalesce(t.IsModeratorOnly,0) as IsMod,
    coalesce(t.IsRequired,0) as IsRequired,
    count(distinct p.Id) filter (where p.PostTypeId=1) over (partition by t.Id) as QuestionCount,
    coalesce(wp.Tags,'') as WikiTags
  from Tags t
  left join Posts p on position('<'||t.TagName||'>' in coalesce(p.Tags, '')) > 0 and p.PostTypeId=1
  left join Posts wp on wp.Id = t.WikiPostId
  where t.ParamId is null -- assuming no extra paramId
),
UserCombined AS (
  select
    ua.UserId,
    ua.DisplayName,
    ua.Reputation,
    ua.HasPosts,
    cpu.NumPosts,
    cpvb.TotalUpvotes,
    cpvb.TotalDownvotes,
    cpvb.TotalComments,
    case when cpvb.TopAnswerScore is null then 0 else cpvb.TopAnswerScore end as TopAnswerScore,
    urh.Rank As UserRankAmongActive
  from UserActivity ua
  left join (
    select OwnerUserId, count(*) as NumPosts
    from Posts
    group by OwnerUserId
  ) cpu on_cpu.OwnerUserId = ua.UserId
  left join (
    select
      p.OwnerUserId,
      sum(case when v.VoteTypeId=2 then 1 else 0 end) as TotalUpvotes,
      sum(case when v.VoteTypeId=3 then 1 else 0 end) as TotalDownvotes,
      sum(pc.CommentCount) as TotalComments,
      max(a.Score) as TopAnswerScore
    from Posts p
    left join Votes v on v.PostId = p.Id
    left join (
      select PostId, count(*) as CommentCount from Comments group by PostId
    ) pc on pc.PostId = p.Id
    left join Posts a on a.ParentId = p.Id and a.PostTypeId=2
    group by p.OwnerUserId
  ) cpvb on cpvb.OwnerUserId = ua.UserId
  left join (
    select UserId, rank() over (order by reputation desc nulls last) Rank
    from Users
  ) urh on urh.UserId = ua.UserId
  where ua.rn=1
)
select distinct 
  uc.DisplayName,
  uc.Reputation,
  uc.NumPosts,
  uc.TotalUpvotes,
  uc.TotalDownvotes,
  uc.TotalComments,
  case
    when uc.TopAnswerScore is null then 0 else uc.TopAnswerScore
  end as HighestUserAnswerScore,
  q.Id as RecentQuestionId,
  co.title as AcceptedAnswerTitle,
  al.AnswerRank,
  crc.CloseReason,
  vt.Name AS MostCommonRecentVoteType,
  tl.denseCountTags,
  tl.ModCount,
  tl.RequiredCount,
  (case when string_agg(distinct t.TagName, ',' order by t.TagName) is null then '' else string_agg(distinct t.TagName, ',' order by t.TagName) end) as UserAnswerTagNames,
  (select count(*) from Votes vs where vs.PostId = co.Id and vs.CreationDate > now() - interval '7 day') as VotesLastWeek
from UserCombined uc
inner join Posts q on q.OwnerUserId = uc.UserId and q.PostTypeId=1
left join Posts co on co.Id = q.AcceptedAnswerId
left join AnswersRanked al on al.QuestionId = q.Id and al.OwnerUserId = uc.UserId and al.AnswerRank = 1
left join FilteredCloseReasons crc on crc.PostId = q.Id
left join Votes v on v.PostId = q.Id
left join VoteTypes vt on vt.Id = v.VoteTypeId
left join lateral (
  select 
    count(distinct case when t.IsModeratorOnly=1 then t.Id else null end) as ModCount,
    count(distinct case when t.IsRequired=1 then t.Id else null end) as RequiredCount,
    count(distinct t.Id) as denseCountTags
  from unnest(string_to_array(coalesce(q.Tags, ''), '><')) as tagname
  join Tags t on t.TagName = tagname
) tl on true
left join LATERAL (
  select distinct t.TagName from Tags t
  join Posts p2 on p2.Guid = uc.UserId and p2.Tags similar to concat('%(', t.TagName, ')%')
  where p2.PostTypeId=2 limit 10
) t on true
order by uc.Reputation desc, q.CreationDate desc
limit 50;