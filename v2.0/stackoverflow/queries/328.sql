with
q as (
  select p.Id as QuestionId,
         p.OwnerUserId as AskerId,
         p.Title,
         p.CreationDate as QuestionCreated,
         p.Score as QuestionScore,
         p.ViewCount,
         coalesce(array_length(string_to_array(nullif(substring(p.Tags, 2, case when length(p.Tags)-2 = -1 then null else length(p.Tags)-2 end), '') , '><'), 1), 0) as TagCount,
         p.Tags,
         p.AcceptedAnswerId,
         p.CreationDate as CreationDate
  from Posts p
  where p.PostTypeId = 1
),
a as (
  select a.Id as AnswerId,
         a.ParentId as QuestionId,
         a.OwnerUserId as AnswererId,
         a.Score as AnswerScore,
         a.CreationDate as AnswerCreated
  from Posts a
  where a.PostTypeId = 2
),
first_last_answers as (
  select
    QuestionId,
    min(AnswerCreated) as FirstAnswerAt,
    max(AnswerCreated) as LastAnswerAt,
    count(*) as AnswerCount,
    sum(case when AnswerScore > 0 then 1 else 0 end) as PositiveAnswers
  from a
  group by QuestionId
),
accepted as (
  select q.QuestionId,
         q.AcceptedAnswerId,
         a.AnswererId as AcceptedAnswererId,
         a.AnswerScore as AcceptedAnswerScore,
         a.AnswerCreated as AcceptedAnswerCreated
  from q
  left join a on a.AnswerId = q.AcceptedAnswerId
),
user_activity as (
  select
    u.Id as UserId,
    u.Reputation,
    u.CreationDate,
    u.UpVotes,
    u.DownVotes,
    (u.UpVotes - u.DownVotes) as NetVotes,
    coalesce(bc_gold.cnt,0) as GoldBadges,
    coalesce(bc_silver.cnt,0) as SilverBadges,
    coalesce(bc_bronze.cnt,0) as BronzeBadges
  from Users u
  left join (
    select UserId, count(*) cnt from Badges where Class = 1 group by UserId
  ) bc_gold on bc_gold.UserId = u.Id
  left join (
    select UserId, count(*) cnt from Badges where Class = 2 group by UserId
  ) bc_silver on bc_silver.UserId = u.Id
  left join (
    select UserId, count(*) cnt from Badges where Class = 3 group by UserId
  ) bc_bronze on bc_bronze.UserId = u.Id
),
question_votes as (
  select v.PostId as QuestionId,
         sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
         sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
         sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites
  from Votes v
  join Posts p on p.Id = v.PostId and p.PostTypeId = 1
  group by v.PostId
),
comment_stats as (
  select
    c.PostId,
    count(*) as CommentCount,
    sum(case when c.Score > 0 then 1 else 0 end) as PositiveComments,
    max(c.Score) as MaxCommentScore,
    min(c.Score) as MinCommentScore
  from Comments c
  group by c.PostId
),
duplicate_links as (
  select pl.PostId as QuestionId,
         sum(case when pl.LinkTypeId = 3 then 1 else 0 end) as DuplicateLinks,
         sum(case when pl.LinkTypeId = 1 then 1 else 0 end) as LinkedLinks
  from PostLinks pl
  group by pl.PostId
),
closures as (
  select
    ph.PostId as QuestionId,
    min(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as FirstClosedAt,
    min(case when ph.PostHistoryTypeId = 11 then ph.CreationDate end) as FirstReopenedAt,
    sum(case when ph.PostHistoryTypeId = 10 then 1 else 0 end) as CloseEvents,
    sum(case when ph.PostHistoryTypeId = 11 then 1 else 0 end) as ReopenEvents,
    max(case when ph.PostHistoryTypeId = 10 then nullif(ph.Comment,'') end) as SomeCloseReasonText
  from PostHistory ph
  join Posts p on p.Id = ph.PostId and p.PostTypeId = 1
  group by ph.PostId
),
hot_bumps as (
  select
    ph.PostId as QuestionId,
    sum(case when ph.PostHistoryTypeId = 50 then 1 else 0 end) as CommunityBumps,
    sum(case when ph.PostHistoryTypeId = 52 then 1 else 0 end) as BecameHot,
    sum(case when ph.PostHistoryTypeId = 53 then 1 else 0 end) as RemovedHot
  from PostHistory ph
  where ph.PostHistoryTypeId in (50,52,53)
  group by ph.PostId
),
title_len as (
  select
    p.Id as QuestionId,
    char_length(coalesce(p.Title, '')) as TitleLen,
    char_length(regexp_replace(coalesce(p.Title,''), '\s+', '', 'g')) as TitleLenNoSpaces
  from Posts p
  where p.PostTypeId = 1
),
ranked_answers as (
  select
    a.QuestionId,
    a.AnswerId,
    a.AnswererId,
    a.AnswerScore,
    a.AnswerCreated,
    row_number() over (partition by a.QuestionId order by a.AnswerScore desc, a.AnswerCreated asc) as rn_score,
    row_number() over (partition by a.QuestionId order by a.AnswerCreated asc) as rn_time
  from a
),
top_answerers as (
  select
    QuestionId,
    AnswerId as TopScoreAnswerId,
    AnswererId as TopScoreAnswererId,
    AnswerScore as TopScore,
    AnswerCreated as TopScoreAnswerCreated
  from ranked_answers
  where rn_score = 1
),
fastest_answerers as (
  select
    QuestionId,
    AnswerId as FirstAnswerId,
    AnswererId as FirstAnswererId,
    AnswerScore as FirstAnswerScore,
    AnswerCreated as FirstAnswerCreated
  from ranked_answers
  where rn_time = 1
),
tag_explode as (
  select
    q.QuestionId,
    unnest(string_to_array(substring(q.Tags, 2, greatest(char_length(q.Tags)-2,0)), '><')) as tag
  from q
  where q.Tags is not null and char_length(q.Tags) >= 2
),
tag_density as (
  select
    QuestionId,
    count(*) as TagItems,
    sum(case when tag ~ '^[a-m]' then 1 else 0 end) as TagAtoM
  from tag_explode
  group by QuestionId
),
question_quality as (
  select
    q.QuestionId,
    (q.QuestionScore + coalesce(qv.UpVotes,0) - coalesce(qv.DownVotes,0)) as NetScore,
    case
      when coalesce(qv.UpVotes,0) + coalesce(qv.DownVotes,0) = 0 then null
      else cast(coalesce(qv.UpVotes,0) as numeric) / nullif(coalesce(qv.UpVotes,0) + coalesce(qv.DownVotes,0),0)
    end as UpvoteRatio,
    coalesce(cs.CommentCount,0) as TotalComments,
    case when q.ViewCount > 0 then cast(q.QuestionScore as numeric) / q.ViewCount else null end as ScorePerView
  from q
  left join question_votes qv on qv.QuestionId = q.QuestionId
  left join comment_stats cs on cs.PostId = q.QuestionId
),
user_pair as (
  select
    q.QuestionId,
    qa.UserId as AskerId,
    qu.UserId as AnswererId,
    qa.Reputation as AskerRep,
    qu.Reputation as AnswererRep,
    qa.NetVotes as AskerNetVotes,
    qu.NetVotes as AnswererNetVotes,
    qa.GoldBadges as AskerGold,
    qu.GoldBadges as AnswererGold
  from q
  left join user_activity qa on qa.UserId = q.AskerId
  left join accepted ac on ac.QuestionId = q.QuestionId
  left join a ans on ans.QuestionId = q.QuestionId
  left join user_activity qu on qu.UserId = ans.AnswererId
),
asker_answerer_gap as (
  select
    QuestionId,
    max(AnswererRep) filter (where AnswererRep is not null) as MaxAnswererRep,
    min(AnswererRep) filter (where AnswererRep is not null) as MinAnswererRep,
    avg(AnswererRep) filter (where AnswererRep is not null) as AvgAnswererRep,
    max(AnswererRep - AskerRep) filter (where AnswererRep is not null and AskerRep is not null) as MaxRepGap,
    avg(cast((AnswererRep - AskerRep) as numeric)) filter (where AnswererRep is not null and AskerRep is not null) as AvgRepGap
  from user_pair
  group by QuestionId
),
question_time_spans as (
  select
    q.QuestionId,
    fl.FirstAnswerAt,
    fl.LastAnswerAt,
    extract(epoch from (fl.FirstAnswerAt - q.QuestionCreated)) as SecToFirstAnswer,
    extract(epoch from (fl.LastAnswerAt - q.QuestionCreated)) as SecToLastAnswer
  from q
  left join first_last_answers fl on fl.QuestionId = q.QuestionId
),
recent_questions as (
  select q.QuestionId
  from q
  where q.CreationDate >= (select max(CreationDate) from Posts where PostTypeId = 1) - interval '365 days'
),
filtered as (
  select q.QuestionId
  from q
  left join closures c on c.QuestionId = q.QuestionId
  where
    coalesce(q.QuestionScore, 0) + coalesce(q.ViewCount, 0) > 0
    and (q.Tags is null or position('sql' in lower(q.Title || ' ' || coalesce(q.Tags,''))) > 0)
    and (c.CloseEvents is null or c.CloseEvents = 0 or (c.ReopenEvents is not null and c.ReopenEvents > 0))
    and (q.AcceptedAnswerId is null or q.AcceptedAnswerId <> -1)
)
select
  q.QuestionId,
  q.Title,
  q.QuestionCreated,
  q.ViewCount,
  tl.TitleLen,
  tl.TitleLenNoSpaces,
  q.TagCount,
  td.TagItems,
  td.TagAtoM,
  qq.NetScore,
  qq.UpvoteRatio,
  qq.TotalComments,
  qq.ScorePerView,
  fl.AnswerCount,
  fl.PositiveAnswers,
  qt.FirstAnswerAt,
  qt.LastAnswerAt,
  qt.SecToFirstAnswer,
  qt.SecToLastAnswer,
  ac.AcceptedAnswerId,
  ac.AcceptedAnswererId,
  ac.AcceptedAnswerScore,
  ac.AcceptedAnswerCreated,
  ta.TopScoreAnswerId,
  ta.TopScoreAnswererId,
  ta.TopScore,
  fa.FirstAnswerId,
  fa.FirstAnswererId,
  fa.FirstAnswerScore,
  fa.FirstAnswerCreated,
  ag.MaxAnswererRep,
  ag.MinAnswererRep,
  ag.AvgAnswererRep,
  ag.MaxRepGap,
  ag.AvgRepGap,
  dl.DuplicateLinks,
  dl.LinkedLinks,
  coalesce(cl.CloseEvents,0) as CloseEvents,
  coalesce(cl.ReopenEvents,0) as ReopenEvents,
  cl.FirstClosedAt,
  cl.FirstReopenedAt,
  hb.CommunityBumps,
  hb.BecameHot,
  hb.RemovedHot,
  case
    when ac.AcceptedAnswererId is not null and fa.FirstAnswererId is not null and ac.AcceptedAnswererId = fa.FirstAnswererId then 'Accepted=First'
    when ac.AcceptedAnswererId is not null and ta.TopScoreAnswererId is not null and ac.AcceptedAnswererId = ta.TopScoreAnswererId then 'Accepted=TopScore'
    when ta.TopScoreAnswererId is not null and fa.FirstAnswererId is not null and ta.TopScoreAnswererId = fa.FirstAnswererId then 'TopScore=First'
    else 'Divergent'
  end as AnswererRoleOverlap,
  case
    when qq.UpvoteRatio is null then 'NoVotes'
    when qq.UpvoteRatio >= 0.9 then 'HighlyUpvoted'
    when qq.UpvoteRatio >= 0.7 then 'Upvoted'
    when qq.UpvoteRatio >= 0.5 then 'Mixed'
    else 'Downvoted'
  end as VoteSkewBucket,
  rank() over (order by coalesce(qq.NetScore, -999999) desc, coalesce(q.ViewCount,0) desc, q.QuestionCreated desc) as GlobalRank,
  dense_rank() over (partition by case when q.ViewCount >= 10000 then 'HighViews' when q.ViewCount >= 1000 then 'MidViews' else 'LowViews' end
                     order by coalesce(qq.NetScore, -999999) desc) as RankWithinViewBand
from filtered f
join q on q.QuestionId = f.QuestionId
left join title_len tl on tl.QuestionId = q.QuestionId
left join tag_density td on td.QuestionId = q.QuestionId
left join question_quality qq on qq.QuestionId = q.QuestionId
left join first_last_answers fl on fl.QuestionId = q.QuestionId
left join question_time_spans qt on qt.QuestionId = q.QuestionId
left join accepted ac on ac.QuestionId = q.QuestionId
left join top_answerers ta on ta.QuestionId = q.QuestionId
left join fastest_answerers fa on fa.QuestionId = q.QuestionId
left join asker_answerer_gap ag on ag.QuestionId = q.QuestionId
left join duplicate_links dl on dl.QuestionId = q.QuestionId
left join closures cl on cl.QuestionId = q.QuestionId
left join hot_bumps hb on hb.QuestionId = q.QuestionId
where q.QuestionId in (
  select QuestionId from recent_questions
  union
  select QuestionId from (
    select QuestionId, ntile(10) over (order by coalesce(qq.NetScore, -999999) desc) as decile
    from question_quality qq
  ) s where s.decile in (1,10)
)
order by GlobalRank
limit 500;