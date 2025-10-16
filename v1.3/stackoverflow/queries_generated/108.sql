-- {"query": "108.sql", "dataset": "stackoverflow", "version": "v1.3", "prompt": "p1", "model": "gpt-5-mini", "temperature": 1.0, "max_tokens": 32768, "reasoning": "low", "input_tokens": 2026, "output_tokens": 2248} 
with
-- explode tags on questions into (PostId, Tag)
question_tags as (
  select p.Id as PostId,
         trim(t) as Tag
  from Posts p
  cross join lateral (
    select regexp_split_to_table(substring(p.Tags from 2 for char_length(p.Tags)-2), '><') as t
  ) s
  where p.PostTypeId = 1 and p.Tags is not null
),
-- aggregate per-user basic metrics
user_base as (
  select u.Id as UserId,
         u.DisplayName,
         u.Reputation,
         count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionsAsked,
         count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswersAuthored,
         count(distinct c.Id) as CommentsMade,
         coalesce(sum(vt_up.cnt),0) as UpVotesGiven, -- votes by this user (as voter)
         coalesce(b.BadgeCount,0) as BadgesTotal,
         coalesce((select max(Ph.CreationDate) from PostHistory Ph where Ph.UserId = u.Id), u.LastAccessDate) as LastModifiedOrAccess
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Comments c on c.UserId = u.Id
  left join (
    select UserId, count(*) as cnt
    from Votes
    where UserId is not null and VoteTypeId = 2
    group by UserId
  ) vt_up on vt_up.UserId = u.Id
  left join (
    select UserId, count(*) as BadgeCount from Badges group by UserId
  ) b on b.UserId = u.Id
  group by u.Id, u.DisplayName, u.Reputation, b.BadgeCount, u.LastAccessDate
),
-- compute per-user received metrics (votes on their posts, avg answer score, accepts)
user_received as (
  select u.Id as UserId,
         coalesce(sum(case when v.VoteTypeId = 2 then 1 else 0 end),0) as UpVotesReceived,
         coalesce(sum(case when v.VoteTypeId = 3 then 1 else 0 end),0) as DownVotesReceived,
         coalesce(sum(case when v.VoteTypeId = 1 then 1 else 0 end),0) as AcceptedCount,
         coalesce(avg(case when p.PostTypeId = 2 then p.Score end),0) filter (where p.PostTypeId = 2) as AvgAnswerScore,
         count(distinct p.Id) as PostsCount
  from Users u
  left join Posts p on p.OwnerUserId = u.Id
  left join Votes v on v.PostId = p.Id
  group by u.Id
),
-- tag expertise: top 3 tags a user answered in by answer count and score
user_tag_expertise as (
  select ut.UserId, ut.Tag,
         sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersInTag,
         sum(case when p.PostTypeId = 2 then p.Score else 0 end) as ScoreInTag,
         row_number() over (partition by ut.UserId order by sum(case when p.PostTypeId = 2 then 1 else 0 end) desc, sum(case when p.PostTypeId = 2 then p.Score else 0 end) desc) as rn
  from question_tags qt
  join Posts q on q.Id = qt.PostId and q.PostTypeId = 1
  join Posts p on p.ParentId = q.Id and p.PostTypeId = 2
  join Users u on p.OwnerUserId = u.Id
  join (select Id as UserId from Users) ut_user on ut_user.UserId = u.Id
  cross join lateral (select u.Id as UserId, qt.Tag) ut
  where u.Id is not null
  group by ut.UserId, qt.Tag
),
top_tags_per_user as (
  select UserId, string_agg(Tag || ' (' || AnswersInTag || '/' || ScoreInTag || ')', ', ' order by AnswersInTag desc, ScoreInTag desc) as TopTags
  from user_tag_expertise
  where rn <= 3
  group by UserId
),
-- compute complex composite score with weighted elements and NULL-safe math, include recency penalty/bonus
user_score as (
  select ub.UserId,
         ub.DisplayName,
         ub.Reputation,
         ub.QuestionsAsked,
         ub.AnswersAuthored,
         ub.CommentsMade,
         ur.UpVotesReceived,
         ur.DownVotesReceived,
         ur.AcceptedCount,
         ur.AvgAnswerScore,
         ub.BadgesTotal,
         coalesce(tp.TopTags, '') as TopTags,
         -- recency: days since last activity, capped and inverted
         greatest(0, 365 - extract(day from (current_timestamp - ub.LastModifiedOrAccess)))::int as RecencyScore,
         -- composite (example): reputation weighted + answers*score + badges bonus - downvotes penalty + recency influence
         (
           (ub.Reputation::numeric * 0.001)
           + (ur.UpVotesReceived * 0.5)
           - (ur.DownVotesReceived * 0.75)
           + (ur.AcceptedCount * 2.0)
           + (ur.AvgAnswerScore * 1.2 * coalesce(NULLIF(ur.AvgAnswerScore,0),1))
           + (ub.AnswersAuthored * 0.8)
           + (ub.QuestionsAsked * 0.2)
           + (ub.CommentsMade * 0.05)
           + (ub.BadgesTotal * 0.3)
           + (greatest(0, least(365, extract(day from (current_timestamp - ub.LastModifiedOrAccess))))/365.0) * 1.5
           + (least(100, greatest(0, (365 - extract(day from (current_timestamp - ub.LastModifiedOrAccess)))))/100.0) * 1.0
         ) as RawComposite
  from user_base ub
  left join user_received ur on ur.UserId = ub.UserId
  left join top_tags_per_user tp on tp.UserId = ub.UserId
),
-- normalize score and rank, include moving average over neighbors by rank for benchmarking window function stress
score_ranked as (
  select us.*,
         dense_rank() over (order by RawComposite desc) as DenseRank,
         rank() over (order by RawComposite desc) as Rank,
         ntile(10) over (order by RawComposite desc) as Decile,
         avg(RawComposite) over (order by RawComposite desc rows between 2 preceding and 2 following) as MovingAvg5,
         -- percentile approximation
         percent_rank() over (order by RawComposite desc) as PercentileRank
  from user_score us
),
-- correlated subquery examples and anti-join/EXCEPT set operations to find users with suspicious voting behavior (voted but never posted)
suspicious_voters as (
  select distinct v.UserId
  from Votes v
  where v.UserId is not null
    and not exists (
      select 1 from Posts p where p.OwnerUserId = v.UserId
    )
    and v.VoteTypeId in (2,3) -- up or down votes
),
-- sample union/except: active_contributors (posted or commented recently) vs lurkers who only vote
active_contributors as (
  select UserId from (
    select OwnerUserId as UserId, max(CreationDate) as dt from Posts group by OwnerUserId
    union
    select UserId, max(CreationDate) from Comments group by UserId
  ) t where UserId is not null and max(dt) is not null
),
lurkers as (
  select distinct v.UserId
  from Votes v
  where v.UserId is not null
  except
  select UserId from active_contributors
),
-- final selection: combine everything, stress test with many expressions, outer joins and correlated fields
final as (
  select sr.UserId,
         sr.DisplayName,
         sr.Reputation,
         sr.QuestionsAsked,
         sr.AnswersAuthored,
         sr.TopTags,
         sr.UpVotesReceived,
         sr.DownVotesReceived,
         sr.AcceptedCount,
         round(sr.AvgAnswerScore::numeric,2) as AvgAnswerScore,
         sr.BadgesTotal,
         sr.RecencyScore,
         round(sr.RawComposite::numeric,4) as RawComposite,
         sr.DenseRank,
         sr.Rank,
         sr.Decile,
         round(sr.MovingAvg5::numeric,4) as MovingAvg5,
         sr.PercentileRank,
         case when s.UserId is not null then true else false end as IsSuspiciousVoter,
         case when l.UserId is not null then true else false end as IsLurker,
         -- correlated subquery for last 3 posts' average score
         (select round(avg(p2.Score)::numeric,2) from Posts p2 where p2.OwnerUserId = sr.UserId order by p2.CreationDate desc limit 3) as AvgScoreLast3Posts,
         -- a complicated string expression combining name, id, and tags with null logic
         coalesce(sr.DisplayName, 'user_'||sr.UserId::text) || ' | id:' || sr.UserId::text ||
           coalesce(' | tags:'||nullif(sr.TopTags,''),'') ||
           coalesce(' | rep:'||sr.Reputation::text,'') as SummaryLine
  from score_ranked sr
  left join suspicious_voters s on s.UserId = sr.UserId
  left join lurkers l on l.UserId = sr.UserId
)
select *
from final
where RawComposite is not null
order by RawComposite desc
limit 50;