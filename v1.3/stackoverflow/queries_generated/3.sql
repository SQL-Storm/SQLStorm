-- {"query": "3.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2027} 
with tag_exploded as (
  select
    p.Id as QuestionId,
    trim(t) as Tag
  from Posts p
  cross join lateral (
    select unnest(string_to_array(substring(coalesce(p.Tags,''),2, greatest(length(coalesce(p.Tags,''))-2,0)), '><')) as t
  ) s
  where p.PostTypeId = 1
),
user_activity as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
    count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
    coalesce(sum(v.VoteTypeId = 2::int)::int,0) as UpVotesGiven,
    coalesce(sum(v.VoteTypeId = 3::int)::int,0) as DownVotesGiven,
    row_number() over (order by u.Reputation desc nulls last, u.Id) as RepRank
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Votes v on v.UserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation
),
question_stats as (
  select
    q.Id,
    q.Title,
    q.OwnerUserId,
    q.CreationDate,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.AcceptedAnswerId,
    coalesce((select count(*) from Comments c where c.PostId = q.Id),0) as CommentCount,
    coalesce((select sum(case when v.VoteTypeId=2 then 1 when v.VoteTypeId=3 then -1 else 0 end) from Votes v where v.PostId = q.Id),0) as VoteScore,
    (select count(*) from PostLinks pl where pl.PostId = q.Id and pl.LinkTypeId = 3) as DuplicateCount,
    (select min(ph.CreationDate) from PostHistory ph where ph.PostId = q.Id and ph.PostHistoryTypeId in (10,11) ) as FirstCloseOrReopen,
    (select array_agg(distinct uh.Tag order by uh.Tag) from tag_exploded uh where uh.QuestionId = q.Id) as TagsArray
  from Posts q
  where q.PostTypeId = 1
),
answers_augmented as (
  select
    a.Id,
    a.ParentId as QuestionId,
    a.OwnerUserId as AnswererId,
    a.CreationDate,
    a.Score,
    a.Body,
    a.CommentCount,
    case when a.Id = q.AcceptedAnswerId then true else false end as IsAccepted,
    dense_rank() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as ScoreRankWithinQuestion,
    rank() over (partition by a.ParentId order by a.CreationDate asc) as ChronoRankWithinQuestion,
    coalesce((select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 2),0) as UpvoteCount,
    coalesce((select count(*) from Votes v where v.PostId = a.Id and v.VoteTypeId = 3),0) as DownvoteCount,
    greatest(coalesce(a.Score,0) + coalesce((select sum(case when v.VoteTypeId=2 then 1 when v.VoteTypeId=3 then -1 else 0 end) from Votes v where v.PostId = a.Id),0),0) as AdjustedScore
  from Posts a
  left join Posts q on q.Id = a.ParentId
  where a.PostTypeId = 2
),
top_users_per_tag as (
  select
    te.Tag,
    ua.UserId,
    ua.DisplayName,
    sum(case when p.PostTypeId=1 then 1 when p.PostTypeId=2 then 1 else 0 end) as Contributions,
    sum(case when p.PostTypeId=1 then coalesce(p.Score,0) else 0 end) as QuestionScoreSum,
    sum(case when p.PostTypeId=2 then coalesce(p.Score,0) else 0 end) as AnswerScoreSum,
    dense_rank() over (partition by te.Tag order by sum(case when p.PostTypeId=2 then coalesce(p.Score,0) else 0 end) desc, ua.Reputation desc) as TagRank
  from tag_exploded te
  join Posts p on p.Id = te.QuestionId
  left join Posts a on a.ParentId = p.Id
  left join Users ua on (ua.Id = p.OwnerUserId or ua.Id = a.OwnerUserId)
  where ua.Id is not null
  group by te.Tag, ua.UserId, ua.DisplayName, ua.Reputation
),
recent_activity as (
  select
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.CreationDate,
    p.LastActivityDate,
    json_build_object(
      'age_days', extract(epoch from (now() - p.CreationDate))/86400,
      'last_active_days', extract(epoch from (now() - p.LastActivityDate))/86400,
      'has_owner', case when p.OwnerUserId is null then false else true end
    ) as MetaBlob
  from Posts p
  where p.CreationDate > now() - interval '365 days'
),
complex_search as (
  select
    qs.Id as QuestionId,
    qs.Title,
    qs.Score,
    qs.ViewCount,
    qs.AnswerCount,
    qs.AcceptedAnswerId,
    coalesce(array_to_string(qs.TagsArray,','),'') as Tags,
    ua.DisplayName as OwnerName,
    ua.Reputation as OwnerRep,
    (select count(*) from answers_augmented aa where aa.QuestionId = qs.Id and aa.IsAccepted) as AcceptedCount,
    (select count(*) from answers_augmented aa where aa.QuestionId = qs.Id and aa.ScoreRankWithinQuestion = 1) as HasTopAnswer,
    (select json_agg(row_to_json(x)) from (
       select a.Id as AnswerId, a.AnswererId, a.IsAccepted, a.Score, a.AdjustedScore
       from answers_augmented a where a.QuestionId = qs.Id order by a.AdjustedScore desc nulls last limit 5
    ) x) as TopAnswersSummary
  from question_stats qs
  left join Users ua on ua.Id = qs.OwnerUserId
  where (qs.Score > 3 or qs.ViewCount > 1000 or qs.AnswerCount > 5)
    and (qs.FirstCloseOrReopen is null or qs.FirstCloseOrReopen > qs.CreationDate + interval '7 days')
)
select
  cs.QuestionId,
  left(cs.Title, 140) as SnippetTitle,
  cs.Score,
  cs.ViewCount,
  cs.AnswerCount,
  cs.AcceptedCount,
  cs.HasTopAnswer,
  cs.Tags,
  cs.OwnerName,
  cs.OwnerRep,
  (select count(*) from Comments c where c.PostId = cs.QuestionId and c.CreationDate > cs.QuestionId::text::timestamp without time zone - interval '100 years') as RecentCommentsHack,
  (select string_agg(distinct t.Tag, ',') from tag_exploded t where t.QuestionId = cs.QuestionId) as TagList,
  (select json_agg(row_to_json(u)) from (
     select ua.UserId, ua.DisplayName, ua.Reputation, ua.QuestionsPosted, ua.AnswersPosted
     from user_activity ua
     where ua.RepRank <= 50
     order by ua.Reputation desc nulls last limit 5
  ) u) as TopSiteUsersSnapshot,
  cs.TopAnswersSummary,
  -- correlate with top_users_per_tag: retrieve top contributor for the first tag if exists
  (select tu.DisplayName from top_users_per_tag tu where tu.Tag = split_part(cs.Tags,',',1) and tu.TagRank = 1 limit 1) as TopContributorForFirstTag,
  -- heavy expression combining string ops, null logic, arithmetic, and set operator
  (
    select
      (sum(coalesce(a.Score,0)) + count(distinct v.Id) * 2 - coalesce(min(u.Reputation),0)) /
      nullif(greatest(1, (select count(*) from answers_augmented aa where aa.QuestionId = cs.QuestionId)),0)::numeric
    from Posts p
    left join answers_augmented a on a.QuestionId = p.Id
    left join Votes v on v.PostId = p.Id and v.CreationDate > now() - interval '30 days'
    left join Users u on u.Id = p.OwnerUserId
    where p.Id = cs.QuestionId
    group by p.Id
  ) as HotnessScore,
  -- combine set operators: union of answerers ids vs voters ids
  (
    select array_agg(distinct id) from (
      select aa.AnswererId as id from answers_augmented aa where aa.QuestionId = cs.QuestionId
      union
      select v.UserId as id from Votes v where v.PostId = cs.QuestionId and v.UserId is not null
    ) s
  ) as Participants,
  now() as SnapshotTaken
from complex_search cs
order by HotnessScore desc nulls last, cs.ViewCount desc
limit 100;