-- {"query": "988.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3150} 
with recent_q as (
  select
    p.Id as QuestionId,
    p.CreationDate as QuestionDate,
    p.OwnerUserId as AskerId,
    p.Score as QuestionScore,
    p.ViewCount,
    p.Title,
    p.Tags,
    coalesce(p.AnswerCount, 0) as AnswerCount,
    p.AcceptedAnswerId
  from Posts p
  where p.PostTypeId = 1
    and p.CreationDate >= (select max(CreationDate) - interval '180 days' from Posts)
),
answer_stats as (
  select
    q.QuestionId,
    count(a.Id) as TotalAnswers,
    sum(case when a.Score > 0 then 1 else 0 end) as PositiveAnswers,
    sum(case when a.OwnerUserId is null then 1 else 0 end) as AnonymousAnswers,
    min(a.CreationDate) filter (where a.ParentId is not null) as FirstAnswerDate,
    max(a.Score) as MaxAnswerScore,
    avg(a.Score::numeric) as AvgAnswerScore
  from recent_q q
  left join Posts a
    on a.PostTypeId = 2 and a.ParentId = q.QuestionId
  group by q.QuestionId
),
accepted_vs_best as (
  select
    q.QuestionId,
    q.AcceptedAnswerId,
    a_max.Id as MaxScoreAnswerId,
    coalesce(a_acc.Score, -999999) as AcceptedScore,
    coalesce(a_max.Score, -999999) as MaxScore,
    case
      when q.AcceptedAnswerId is null then 'none'
      when q.AcceptedAnswerId = a_max.Id then 'accepted_is_best'
      else 'accepted_not_best'
    end as AcceptanceQuality
  from recent_q q
  left join lateral (
    select a.Id, a.Score
    from Posts a
    where a.PostTypeId = 2 and a.ParentId = q.QuestionId
    order by a.Score desc nulls last, a.Id
    limit 1
  ) a_max on true
  left join Posts a_acc on a_acc.Id = q.AcceptedAnswerId
),
question_votes as (
  select
    v.PostId as QuestionId,
    sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
    sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
    sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites
  from Votes v
  join recent_q q on q.QuestionId = v.PostId
  group by v.PostId
),
comment_agg as (
  select
    c.PostId as QuestionId,
    count(*) filter (where c.Score > 0) as PosComments,
    max(c.Score) as MaxCommentScore,
    string_agg(substr(coalesce(c.Text, ''), 1, 50), ' | ' order by c.Score desc, c.Id) as SampleComments
  from Comments c
  join recent_q q on q.QuestionId = c.PostId
  group by c.PostId
),
edits as (
  select
    ph.PostId as QuestionId,
    count(*) filter (where ph.PostHistoryTypeId in (4,5,6)) as EditCount,
    min(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6)) as FirstEditDate,
    max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6)) as LastEditDate,
    count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotesLogged,
    max(case when ph.PostHistoryTypeId = 10 then ph.Comment end) as LastCloseReasonCode
  from PostHistory ph
  join recent_q q on q.QuestionId = ph.PostId
  group by ph.PostId
),
tag_expanded as (
  select
    q.QuestionId,
    unnest(string_to_array(substring(q.Tags, 2, greatest(length(q.Tags)-2,0)), '><')) as tag
  from recent_q q
),
tag_quality as (
  select
    te.QuestionId,
    count(*) as TagCount,
    sum(case when t.IsModeratorOnly then 1 else 0 end) as ModOnlyTags,
    max(t.Count) as MaxTagUsage,
    avg(t.Count::numeric) as AvgTagUsage
  from tag_expanded te
  left join Tags t on lower(t.TagName) = lower(te.tag)
  group by te.QuestionId
),
asker as (
  select
    u.Id as UserId,
    u.DisplayName,
    u.Reputation,
    u.UpVotes,
    u.DownVotes,
    u.Views as ProfileViews,
    date_trunc('day', u.CreationDate) as UserSince
  from Users u
),
asker_badges as (
  select
    b.UserId,
    count(*) as BadgeCount,
    sum(case when b.Class = 1 then 1 else 0 end) as Gold,
    sum(case when b.Class = 2 then 1 else 0 end) as Silver,
    sum(case when b.Class = 3 then 1 else 0 end) as Bronze,
    count(*) filter (where b.TagBased = 1) as TagBadges
  from Badges b
  group by b.UserId
),
dup_links as (
  select
    pl.PostId as QuestionId,
    count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks,
    count(*) filter (where pl.LinkTypeId = 1) as LinkedLinks,
    min(pl.CreationDate) as FirstLinkDate
  from PostLinks pl
  join recent_q q on q.QuestionId = pl.PostId
  group by pl.PostId
),
hot_bumps as (
  select
    ph.PostId as QuestionId,
    count(*) filter (where ph.PostHistoryTypeId = 50) as CommunityBumps,
    count(*) filter (where ph.PostHistoryTypeId = 52) as HotSelected,
    count(*) filter (where ph.PostHistoryTypeId = 53) as HotRemoved
  from PostHistory ph
  join recent_q q on q.QuestionId = ph.PostId
  group by ph.PostId
),
time_to_first_answer as (
  select
    q.QuestionId,
    extract(epoch from (min(a.CreationDate) - q.QuestionDate)) / 3600.0 as HoursToFirstAnswer
  from recent_q q
  left join Posts a on a.PostTypeId = 2 and a.ParentId = q.QuestionId
  group by q.QuestionId, q.QuestionDate
),
score_rank as (
  select
    q.QuestionId,
    q.QuestionScore,
    ntile(10) over (order by q.QuestionScore nulls last) as ScoreDecile,
    rank() over (order by q.QuestionScore desc nulls last, q.ViewCount desc nulls last) as ScoreRank
  from recent_q q
),
view_anomalies as (
  select
    q.QuestionId,
    case
      when q.ViewCount is null then 'unknown'
      when q.ViewCount = 0 and q.AnswerCount > 0 then 'zero_views_has_answers'
      when q.ViewCount > 100000 and q.AnswerCount = 0 then 'high_views_no_answers'
      else 'normal'
    end as ViewAnomalyFlag
  from recent_q q
),
question_engagement as (
  select
    q.QuestionId,
    coalesce(v.UpVotes,0) - coalesce(v.DownVotes,0) as NetVotes,
    coalesce(v.Favorites,0) as Favorites,
    coalesce(c.PosComments,0) as PositiveComments,
    coalesce(c.MaxCommentScore,0) as MaxCommentScore
  from recent_q q
  left join question_votes v on v.QuestionId = q.QuestionId
  left join comment_agg c on c.QuestionId = q.QuestionId
),
normalized as (
  select
    q.QuestionId,
    q.Title,
    q.Tags,
    q.ViewCount,
    q.QuestionScore,
    coalesce(asw.TotalAnswers,0) as TotalAnswers,
    coalesce(asw.PositiveAnswers,0) as PositiveAnswers,
    coalesce(asw.AvgAnswerScore,0) as AvgAnswerScore,
    ev.EditCount,
    ev.CloseVotesLogged,
    tq.TagCount,
    tq.AvgTagUsage,
    eg.NetVotes,
    eg.Favorites,
    eg.PositiveComments,
    eg.MaxCommentScore,
    ttfa.HoursToFirstAnswer,
    sv.ScoreDecile,
    sv.ScoreRank,
    avb.AcceptanceQuality,
    va.ViewAnomalyFlag,
    hl.CommunityBumps,
    hl.HotSelected,
    hl.HotRemoved,
    dl.DuplicateLinks,
    dl.LinkedLinks
  from recent_q q
  left join answer_stats asw on asw.QuestionId = q.QuestionId
  left join edits ev on ev.QuestionId = q.QuestionId
  left join tag_quality tq on tq.QuestionId = q.QuestionId
  left join question_engagement eg on eg.QuestionId = q.QuestionId
  left join time_to_first_answer ttfa on ttfa.QuestionId = q.QuestionId
  left join score_rank sv on sv.QuestionId = q.QuestionId
  left join accepted_vs_best avb on avb.QuestionId = q.QuestionId
  left join view_anomalies va on va.QuestionId = q.QuestionId
  left join hot_bumps hl on hl.QuestionId = q.QuestionId
  left join dup_links dl on dl.QuestionId = q.QuestionId
),
user_enriched as (
  select
    q.QuestionId,
    q.Title,
    q.Tags,
    q.ViewCount,
    q.QuestionScore,
    q.TotalAnswers,
    q.PositiveAnswers,
    q.AvgAnswerScore,
    q.EditCount,
    q.CloseVotesLogged,
    q.TagCount,
    q.AvgTagUsage,
    q.NetVotes,
    q.Favorites,
    q.PositiveComments,
    q.MaxCommentScore,
    q.HoursToFirstAnswer,
    q.ScoreDecile,
    q.ScoreRank,
    q.AcceptanceQuality,
    q.ViewAnomalyFlag,
    q.CommunityBumps,
    q.HotSelected,
    q.HotRemoved,
    q.DuplicateLinks,
    q.LinkedLinks,
    u.DisplayName as AskerName,
    u.Reputation as AskerReputation,
    ub.BadgeCount as AskerBadges,
    ub.Gold as AskerGold,
    ub.Silver as AskerSilver,
    ub.Bronze as AskerBronze,
    ub.TagBadges as AskerTagBadges,
    u.UserSince
  from normalized q
  join recent_q rq on rq.QuestionId = q.QuestionId
  left join asker u on u.UserId = rq.AskerId
  left join asker_badges ub on ub.UserId = rq.AskerId
),
outlier_flags as (
  select
    ue.*,
    case when ue.TotalAnswers = 0 and ue.QuestionScore > 0 then 1 else 0 end as Flag_UnansweredButUpvoted,
    case when ue.TotalAnswers > 10 and ue.AvgAnswerScore < 0 then 1 else 0 end as Flag_ManyAnswersLowQuality,
    case when ue.HoursToFirstAnswer is not null and ue.HoursToFirstAnswer > 168 then 1 else 0 end as Flag_SlowFirstAnswer,
    case when ue.AskerReputation is not null and ue.AskerReputation < 50 and ue.QuestionScore > 10 then 1 else 0 end as Flag_NewbiePopular,
    case when ue.TagCount is not null and ue.TagCount > 5 then 1 else 0 end as Flag_ManyTags
  from user_enriched ue
),
final_scored as (
  select
    ofl.*,
    (
      coalesce(ofl.NetVotes,0)*2
      + coalesce(ofl.Favorites,0)*3
      + coalesce(ofl.PositiveComments,0)
      + coalesce(ofl.TotalAnswers,0)
      + case when ofl.AcceptanceQuality = 'accepted_is_best' then 5
             when ofl.AcceptanceQuality = 'accepted_not_best' then 2
             else 0 end
      + case when ofl.ViewAnomalyFlag = 'high_views_no_answers' then -3 else 0 end
      + coalesce(ofl.CommunityBumps,0)
      + coalesce(ofl.HotSelected,0)*4
      - coalesce(ofl.HotRemoved,0)*2
      - coalesce(ofl.DuplicateLinks,0)
    )::numeric as EngagementScore
  from outlier_flags ofl
)
select
  fs.QuestionId,
  coalesce(fs.Title, '(no title)') as Title,
  fs.AskerName,
  fs.AskerReputation,
  fs.UserSince,
  fs.Tags,
  fs.ViewCount,
  fs.QuestionScore,
  fs.NetVotes,
  fs.Favorites,
  fs.TotalAnswers,
  fs.PositiveAnswers,
  round(fs.AvgAnswerScore::numeric, 2) as AvgAnswerScore,
  round(fs.HoursToFirstAnswer::numeric, 2) as HoursToFirstAnswer,
  fs.EditCount,
  fs.CloseVotesLogged,
  fs.TagCount,
  round(fs.AvgTagUsage::numeric, 1) as AvgTagUsage,
  fs.ScoreDecile,
  fs.ScoreRank,
  fs.AcceptanceQuality,
  fs.ViewAnomalyFlag,
  fs.CommunityBumps,
  fs.HotSelected,
  fs.HotRemoved,
  fs.DuplicateLinks,
  fs.LinkedLinks,
  fs.Flag_UnansweredButUpvoted,
  fs.Flag_ManyAnswersLowQuality,
  fs.Flag_SlowFirstAnswer,
  fs.Flag_NewbiePopular,
  fs.Flag_ManyTags,
  fs.EngagementScore,
  rank() over (order by fs.EngagementScore desc nulls last, fs.NetVotes desc, fs.ViewCount desc) as EngagementRank,
  dense_rank() over (partition by fs.ScoreDecile order by fs.EngagementScore desc nulls last) as RankWithinScoreDecile
from final_scored fs
where coalesce(fs.TagCount, 0) > 0
  and (
    fs.EngagementScore > (
      select avg(EngagementScore) from final_scored
    )
    or fs.Flag_SlowFirstAnswer = 1
    or fs.ViewAnomalyFlag <> 'normal'
  )
order by fs.EngagementScore desc nulls last, fs.NetVotes desc, fs.ViewCount desc
limit 250;