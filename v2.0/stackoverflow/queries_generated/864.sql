-- {"query": "864.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3106} 
with
recent_posts as (
  select
    p.Id,
    p.PostTypeId,
    p.OwnerUserId,
    p.ParentId,
    p.AcceptedAnswerId,
    p.Score,
    p.ViewCount,
    p.AnswerCount,
    p.CommentCount,
    p.CreationDate,
    p.LastActivityDate,
    p.Title,
    p.Tags,
    coalesce(nullif(trim(p.OwnerDisplayName), ''), u.DisplayName, 'Anonymous') as OwnerName,
    u.Reputation,
    case when p.ClosedDate is not null then 1 else 0 end as IsClosed
  from Posts p
  left join Users u on u.Id = p.OwnerUserId
  where p.CreationDate >= (select date_trunc('month', max(CreationDate)) - interval '6 months' from Posts)
),
votes_agg as (
  select
    v.PostId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
    sum(case when v.VoteTypeId in (8,9) then coalesce(v.BountyAmount,0) else 0 end) as BountyTotal,
    min(v.CreationDate) as FirstVoteAt,
    max(v.CreationDate) as LastVoteAt
  from Votes v
  group by v.PostId
),
comments_agg as (
  select
    c.PostId,
    count(*) as CommentTotal,
    max(c.Score) as MaxCommentScore,
    sum(case when c.Score > 0 then 1 else 0 end) as PositiveComments,
    min(c.CreationDate) as FirstCommentAt,
    max(c.CreationDate) as LastCommentAt
  from Comments c
  group by c.PostId
),
postlinks_summary as (
  select
    pl.PostId,
    sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as LinkedOutCount,
    sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as DuplicateOfCount
  from PostLinks pl
  group by pl.PostId
),
question_core as (
  select
    rp.*,
    array_length(string_to_array(substring(rp.Tags, 2, greatest(length(rp.Tags)-2,0)), '><'), 1) as TagCount,
    case when rp.PostTypeId = 1 then 1 else 0 end as IsQuestion,
    case when rp.PostTypeId = 2 then 1 else 0 end as IsAnswer
  from recent_posts rp
),
answers_per_question as (
  select
    q.Id as QuestionId,
    count(a.Id) as AnswerTotal,
    max(a.Score) as MaxAnswerScore,
    sum(case when a.Id = q.AcceptedAnswerId then 1 else 0 end) as HasAcceptedAnswer
  from question_core q
  left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
  where q.PostTypeId = 1
  group by q.Id
),
user_badge_density as (
  select
    u.Id as UserId,
    count(b.Id) as BadgeCount,
    case when count(distinct date_trunc('month', b.Date)) = 0 then 0.0
         else count(b.Id)::numeric / count(distinct date_trunc('month', b.Date)) end as BadgesPerActiveMonth
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id
),
post_edits as (
  select
    ph.PostId,
    count(*) filter (where ph.PostHistoryTypeId in (4,5,6,7,8,9,24)) as EditEvents,
    count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotesEvents,
    max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6,7,8,9,24)) as LastEditAt,
    max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as LastCloseVoteAt,
    sum(case when ph.PostHistoryTypeId = 10 and ph.Comment ~ '^[0-9]+' then 1 else 0 end) as CloseReasonsCount
  from PostHistory ph
  group by ph.PostId
),
tag_expansion as (
  select
    q.Id as PostId,
    unnest(string_to_array(substring(q.Tags, 2, greatest(length(q.Tags)-2,0)), '><')) as TagName
  from question_core q
  where q.PostTypeId = 1 and q.Tags is not null and q.Tags <> ''
),
hot_tag_scores as (
  select
    te.PostId,
    sum(ln(count(*))) over (partition by te.PostId) as TagEntropy,
    sum(coalesce(t.Count, 0)) as TotalTagGlobalCount,
    max(case when t.IsModeratorOnly then 1 else 0 end) as HasModOnlyTag
  from tag_expansion te
  left join Tags t on lower(t.TagName) = lower(te.TagName)
  group by te.PostId
),
activity_windows as (
  select
    rp.Id,
    rp.CreationDate,
    rp.LastActivityDate,
    extract(epoch from (coalesce(rp.LastActivityDate, rp.CreationDate) - rp.CreationDate)) / 3600.0 as ActiveHours,
    row_number() over (order by rp.CreationDate desc) as rn_recent,
    dense_rank() over (order by coalesce(rp.Score,0) desc, coalesce(rp.ViewCount,0) desc) as rk_popular
  from recent_posts rp
),
dup_network as (
  select
    q.Id as QuestionId,
    sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as DuplicateEdges,
    count(distinct pl.RelatedPostId) filter (where pl.LinkTypeId = 3) as UniqueDuplicates
  from question_core q
  left join PostLinks pl on pl.PostId = q.Id
  where q.PostTypeId = 1
  group by q.Id
),
owner_activity as (
  select
    rp.Id as PostId,
    coalesce(ua.Reputation, 0) as OwnerRep,
    coalesce(ua.UpVotes, 0) as OwnerUpVotes,
    coalesce(ua.DownVotes, 0) as OwnerDownVotes,
    coalesce(ua.Views, 0) as OwnerProfileViews,
    coalesce(ub.BadgesPerActiveMonth, 0.0) as OwnerBadgesPerActiveMonth
  from recent_posts rp
  left join Users ua on ua.Id = rp.OwnerUserId
  left join user_badge_density ub on ub.UserId = rp.OwnerUserId
),
scores as (
  select
    q.Id as PostId,
    coalesce(v.UpVotes,0) - coalesce(v.DownVotes,0) as NetVotes,
    coalesce(v.UpVotes,0) as UpVotes,
    coalesce(v.DownVotes,0) as DownVotes,
    coalesce(v.Favorites,0) as Favorites,
    coalesce(v.BountyTotal,0) as BountyTotal,
    coalesce(c.CommentTotal,0) as CommentTotal,
    coalesce(c.MaxCommentScore,0) as MaxCommentScore
  from question_core q
  left join votes_agg v on v.PostId = q.Id
  left join comments_agg c on c.PostId = q.Id
),
question_quality as (
  select
    q.Id as PostId,
    q.OwnerName,
    q.Reputation,
    q.Score,
    q.ViewCount,
    q.AnswerCount,
    q.CommentCount,
    q.TagCount,
    q.IsClosed,
    apq.AnswerTotal,
    apq.MaxAnswerScore,
    apq.HasAcceptedAnswer,
    s.NetVotes,
    s.UpVotes,
    s.DownVotes,
    s.Favorites,
    s.BountyTotal,
    s.CommentTotal,
    s.MaxCommentScore,
    coalesce(he.TagEntropy, 0) as TagEntropy,
    coalesce(he.TotalTagGlobalCount, 0) as TotalTagGlobalCount,
    coalesce(he.HasModOnlyTag, 0) as HasModOnlyTag,
    coalesce(pls.LinkedOutCount, 0) as LinkedOutCount,
    coalesce(pls.DuplicateOfCount, 0) as DuplicateOfCount,
    coalesce(pe.EditEvents, 0) as EditEvents,
    pe.LastEditAt,
    coalesce(pe.CloseVotesEvents, 0) as CloseVotesEvents,
    pe.LastCloseVoteAt,
    coalesce(dn.DuplicateEdges, 0) as DuplicateEdges,
    coalesce(dn.UniqueDuplicates, 0) as UniqueDuplicates
  from question_core q
  left join answers_per_question apq on apq.QuestionId = q.Id
  left join scores s on s.PostId = q.Id
  left join hot_tag_scores he on he.PostId = q.Id
  left join postlinks_summary pls on pls.PostId = q.Id
  left join post_edits pe on pe.PostId = q.Id
  left join dup_network dn on dn.QuestionId = q.Id
  where q.PostTypeId = 1
),
ranked as (
  select
    qq.*,
    oa.OwnerRep,
    oa.OwnerUpVotes,
    oa.OwnerDownVotes,
    oa.OwnerProfileViews,
    oa.OwnerBadgesPerActiveMonth,
    aw.ActiveHours,
    aw.rn_recent,
    aw.rk_popular,
    coalesce(qq.NetVotes,0)::numeric / nullif(qq.ViewCount,0) as VotesPerView,
    coalesce(qq.AnswerTotal,0)::numeric / nullif(qq.ViewCount,0) as AnswersPerView,
    case
      when qq.HasAcceptedAnswer = 1 then 1
      when qq.AnswerTotal > 0 and qq.MaxAnswerScore >= 1 then 0.5
      else 0
    end as AcceptanceSignal,
    -- composite score blending various signals
    (
      coalesce(qq.NetVotes,0) * 1.0
      + coalesce(qq.Favorites,0) * 2.0
      + coalesce(qq.BountyTotal,0) * 0.01
      + coalesce(qq.AnswerTotal,0) * 0.5
      + coalesce(qq.MaxAnswerScore,0) * 0.25
      + coalesce(qq.TagEntropy,0) * 0.1
      - coalesce(qq.DuplicateOfCount,0) * 3.0
      - coalesce(qq.CloseVotesEvents,0) * 2.0
    ) as CompositeScore
  from question_quality qq
  left join owner_activity oa on oa.PostId = qq.PostId
  left join activity_windows aw on aw.Id = qq.PostId
),
filtered as (
  select
    r.*,
    row_number() over (
      partition by (r.OwnerName is null), coalesce(r.TagCount,0) >= 5
      order by r.CompositeScore desc, r.NetVotes desc, r.ViewCount desc, r.PostId
    ) as rn_partition
  from ranked r
  where
    (r.ViewCount is null or r.ViewCount >= 10)
    and (r.Score is null or r.Score >= -5)
    and (r.TagCount is null or r.TagCount between 1 and 10)
),
-- set operators to stress planner
top_recent as (
  select PostId from filtered where rn_recent <= 500
),
top_popular as (
  select PostId from filtered where rk_popular <= 500
),
union_set as (
  select PostId from top_recent
  union
  select PostId from top_popular
),
intersect_set as (
  select PostId from top_recent
  intersect
  select PostId from top_popular
),
final_candidates as (
  select
    f.*
  from filtered f
  where f.PostId in (select PostId from union_set)
),
null_logic_checks as (
  select
    fc.*,
    coalesce(nullif(btrim(fc.OwnerName), ''), 'Unknown') as SafeOwnerName,
    case when fc.LastEditAt is null and fc.EditEvents > 0 then 1 else 0 end as EditInconsistency,
    case when fc.CloseVotesEvents > 0 and fc.IsClosed = 0 then 1 else 0 end as PotentiallyReopened
  from final_candidates fc
)
select
  nlc.PostId,
  nlc.SafeOwnerName as OwnerName,
  nlc.Reputation as OwnerReputation,
  nlc.ViewCount,
  nlc.Score as PostScore,
  nlc.NetVotes,
  nlc.UpVotes,
  nlc.DownVotes,
  nlc.Favorites,
  nlc.BountyTotal,
  nlc.AnswerTotal,
  nlc.HasAcceptedAnswer,
  nlc.AcceptanceSignal,
  nlc.CommentTotal,
  nlc.MaxCommentScore,
  nlc.TagCount,
  nlc.TagEntropy,
  nlc.TotalTagGlobalCount,
  nlc.HasModOnlyTag,
  nlc.LinkedOutCount,
  nlc.DuplicateOfCount,
  nlc.DuplicateEdges,
  nlc.UniqueDuplicates,
  nlc.EditEvents,
  nlc.LastEditAt,
  nlc.CloseVotesEvents,
  nlc.LastCloseVoteAt,
  nlc.ActiveHours,
  nlc.OwnerRep,
  nlc.OwnerUpVotes,
  nlc.OwnerDownVotes,
  nlc.OwnerProfileViews,
  nlc.OwnerBadgesPerActiveMonth,
  nlc.CompositeScore,
  case when nlc.PostId in (select PostId from intersect_set) then 'both' else 'either' end as InTopSets,
  nlc.rn_recent,
  nlc.rk_popular,
  nlc.rn_partition,
  nlc.EditInconsistency,
  nlc.PotentiallyReopened
from null_logic_checks nlc
order by
  InTopSets desc,
  nlc.CompositeScore desc,
  nlc.NetVotes desc,
  nlc.ViewCount desc
limit 250;