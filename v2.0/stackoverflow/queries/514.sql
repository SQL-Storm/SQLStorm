-- {"query": "514.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3117}
with
q as (
  select
    p.Id as QuestionId,
    p.CreationDate as QuestionCreated,
    p.Score as QuestionScore,
    p.ViewCount,
    p.OwnerUserId as QuestionOwnerId,
    p.Tags,
    p.Title,
    coalesce(nullif(trim(p.OwnerDisplayName), ''), u.DisplayName, '(unknown)') as QuestionOwnerName,
    date_trunc('month', p.CreationDate) as q_month
  from Posts p
  left join Users u on u.Id = p.OwnerUserId
  where p.PostTypeId = 1
),
answers as (
  select
    a.ParentId as QuestionId,
    a.Id as AnswerId,
    a.OwnerUserId as AnswerOwnerId,
    a.Score as AnswerScore,
    a.CreationDate as AnswerCreated,
    row_number() over (partition by a.ParentId order by a.Score desc nulls last, a.CreationDate asc) as rn_score_desc,
    row_number() over (partition by a.ParentId order by a.CreationDate asc) as rn_first
  from Posts a
  where a.PostTypeId = 2
),
first_answer as (
  select QuestionId, AnswerId as FirstAnswerId, AnswerOwnerId as FirstAnswerOwnerId, AnswerScore as FirstAnswerScore, AnswerCreated as FirstAnswerCreated
  from answers
  where rn_first = 1
),
top_answer as (
  select QuestionId, AnswerId as TopAnswerId, AnswerOwnerId as TopAnswerOwnerId, AnswerScore as TopAnswerScore, AnswerCreated as TopAnswerCreated
  from answers
  where rn_score_desc = 1
),
votes_q as (
  select v.PostId as QuestionId,
         sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end) as NetVotesQ,
         count(*) filter (where v.VoteTypeId = 5) as FavoritesQ
  from Votes v
  group by v.PostId
),
votes_a as (
  select a.ParentId as QuestionId,
         sum(case when v.VoteTypeId = 2 then 1 when v.VoteTypeId = 3 then -1 else 0 end) as NetVotesAns
  from Posts a
  join Votes v on v.PostId = a.Id
  where a.PostTypeId = 2
  group by a.ParentId
),
dup_links as (
  select pl.PostId as QuestionId,
         count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks,
         count(*) filter (where pl.LinkTypeId = 1) as LinkedLinks,
         max(pl.CreationDate) as LastLinkDate
  from PostLinks pl
  group by pl.PostId
),
closures as (
  select ph.PostId as QuestionId,
         min(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as FirstClosed,
         min(ph.CreationDate) filter (where ph.PostHistoryTypeId = 11) as FirstReopened,
         count(*) filter (where ph.PostHistoryTypeId = 10) as CloseEvents,
         count(*) filter (where ph.PostHistoryTypeId = 11) as ReopenEvents,
         max(case when ph.PostHistoryTypeId = 10 then nullif(ph.Comment, '') end) as LastCloseReasonIdText
  from PostHistory ph
  group by ph.PostId
),
comments_agg as (
  select c.PostId as QuestionId,
         count(*) as CommentCount,
         max(c.CreationDate) as LastCommentAt,
         string_agg(substring(coalesce(c.Text,''), 1, 40), ' | ' order by c.CreationDate desc) as RecentCommentSnippets
  from Comments c
  group by c.PostId
),
owner_stats as (
  select
    u.Id as UserId,
    count(*) filter (where b.Class = 1) as GoldBadges,
    count(*) filter (where b.Class = 2) as SilverBadges,
    count(*) filter (where b.Class = 3) as BronzeBadges,
    max(b.Date) as LastBadgeAt,
    sum(coalesce(u.UpVotes,0)) as TotalUpVotesReported,
    sum(coalesce(u.DownVotes,0)) as TotalDownVotesReported
  from Users u
  left join Badges b on b.UserId = u.Id
  group by u.Id, u.UpVotes, u.DownVotes
),
tag_explode as (
  select
    q.QuestionId,
    unnest(string_to_array(substring(q.Tags, 2, greatest(length(q.Tags)-2,0)), '><')) as tag
  from q
  where q.Tags is not null and q.Tags like '<%>'
),
tag_stats as (
  select
    te.QuestionId,
    count(*) as TagCount,
    min(t.Count) as MinTagGlobalCount,
    max(t.Count) as MaxTagGlobalCount,
    sum(t.Count) as SumTagGlobalCount,
    string_agg(te.tag, ',' order by t.Count desc nulls last) as TagsOrderedByGlobalPopularity
  from tag_explode te
  left join Tags t on t.TagName = te.tag
  group by te.QuestionId
),
question_activity as (
  select
    q.QuestionId,
    q.QuestionCreated,
    coalesce(c.LastCommentAt, q.QuestionCreated) as LastInteraction,
    extract(epoch from (coalesce(c.LastCommentAt, q.QuestionCreated) - q.QuestionCreated)) as SecondsToLastInteraction
  from q
  left join comments_agg c on c.QuestionId = q.QuestionId
),
accepted as (
  select
    q.Id as QuestionId,
    q.AcceptedAnswerId
  from Posts q
  where q.PostTypeId = 1
),
answer_lag as (
  select
    a.ParentId as QuestionId,
    avg(extract(epoch from (a.CreationDate - q.CreationDate))) as AvgSecondsToAnswer,
    min(extract(epoch from (a.CreationDate - q.CreationDate))) as MinSecondsToAnswer,
    max(extract(epoch from (a.CreationDate - q.CreationDate))) as MaxSecondsToAnswer
  from Posts a
  join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
  where a.PostTypeId = 2
  group by a.ParentId
),
user_recent_activity as (
  select
    p.OwnerUserId as UserId,
    count(*) filter (where p.PostTypeId = 1) as QuestionsAuthored,
    count(*) filter (where p.PostTypeId = 2) as AnswersAuthored,
    max(p.LastActivityDate) as LastPostActivity,
    date_trunc('month', max(p.LastActivityDate)) as last_act_month
  from Posts p
  where p.OwnerUserId is not null
  group by p.OwnerUserId
),
ranked_questions as (
  select
    q.*,
    coalesce(vq.NetVotesQ, 0) as NetVotesQ,
    coalesce(va.NetVotesAns, 0) as NetVotesAnsAgg,
    coalesce(vq.FavoritesQ, 0) as FavoritesQ,
    coalesce(dl.DuplicateLinks, 0) as DuplicateLinks,
    coalesce(dl.LinkedLinks, 0) as LinkedLinks,
    dl.LastLinkDate,
    cl.FirstClosed,
    cl.FirstReopened,
    cl.CloseEvents,
    cl.ReopenEvents,
    cl.LastCloseReasonIdText,
    ca.CommentCount,
    ca.LastCommentAt,
    ca.RecentCommentSnippets,
    ts.TagCount,
    ts.MinTagGlobalCount,
    ts.MaxTagGlobalCount,
    ts.SumTagGlobalCount,
    ts.TagsOrderedByGlobalPopularity,
    qa.SecondsToLastInteraction,
    al.AvgSecondsToAnswer,
    al.MinSecondsToAnswer,
    al.MaxSecondsToAnswer,
    fa.FirstAnswerId,
    fa.FirstAnswerOwnerId,
    fa.FirstAnswerScore,
    fa.FirstAnswerCreated,
    ta.TopAnswerId,
    ta.TopAnswerOwnerId,
    ta.TopAnswerScore,
    ta.TopAnswerCreated,
    a.AcceptedAnswerId,
    case
      when a.AcceptedAnswerId is not null then
        case when a.AcceptedAnswerId = ta.TopAnswerId then 'Accepted=Top'
             when a.AcceptedAnswerId = fa.FirstAnswerId then 'Accepted=First'
             else 'Accepted=Other' end
      else 'NoAccepted'
    end as AcceptanceCategory
  from q
  left join votes_q vq on vq.QuestionId = q.QuestionId
  left join votes_a va on va.QuestionId = q.QuestionId
  left join dup_links dl on dl.QuestionId = q.QuestionId
  left join closures cl on cl.QuestionId = q.QuestionId
  left join comments_agg ca on ca.QuestionId = q.QuestionId
  left join tag_stats ts on ts.QuestionId = q.QuestionId
  left join question_activity qa on qa.QuestionId = q.QuestionId
  left join answer_lag al on al.QuestionId = q.QuestionId
  left join first_answer fa on fa.QuestionId = q.QuestionId
  left join top_answer ta on ta.QuestionId = q.QuestionId
  left join accepted a on a.QuestionId = q.QuestionId
),
scored as (
  select
    r.*,
    (
      coalesce(r.NetVotesQ,0) * 2
      + coalesce(r.FavoritesQ,0)
      + coalesce(r.NetVotesAnsAgg,0) * 0.5
      + least(coalesce(r.ViewCount,0) / 50.0, 1000)
      - coalesce(r.DuplicateLinks,0) * 3
      - case when r.FirstClosed is not null then 10 else 0 end
      + case when r.TagCount >= 3 then 5 else 0 end
      + case when r.AcceptanceCategory = 'Accepted=Top' then 8
             when r.AcceptanceCategory = 'Accepted=First' then 5
             when r.AcceptanceCategory = 'Accepted=Other' then 2
             else 0 end
      + case when r.FirstAnswerScore >= 5 then 4 else 0 end
      + case when r.TopAnswerScore >= 10 then 6 else 0 end
      - coalesce(r.CommentCount,0) * 0.2
      - coalesce(r.SecondsToLastInteraction,0) / 86400.0
    ) as HeuristicScore
  from ranked_questions r
),
user_enriched as (
  select
    r.QuestionId,
    r.QuestionOwnerId,
    u.Reputation,
    u.CreationDate as UserCreated,
    u.Location,
    u.WebsiteUrl,
    os.GoldBadges,
    os.SilverBadges,
    os.BronzeBadges,
    os.LastBadgeAt,
    ura.QuestionsAuthored,
    ura.AnswersAuthored,
    ura.LastPostActivity,
    dense_rank() over (partition by coalesce(nullif(trim(u.Location), ''), 'Unknown') order by u.Reputation desc nulls last) as RankInLocation
  from ranked_questions r
  left join Users u on u.Id = r.QuestionOwnerId
  left join owner_stats os on os.UserId = u.Id
  left join user_recent_activity ura on ura.UserId = u.Id
),
final_rank as (
  select
    s.*,
    ue.Reputation,
    ue.Location,
    ue.GoldBadges,
    ue.SilverBadges,
    ue.BronzeBadges,
    ue.RankInLocation,
    pct.p90_score,
    row_number() over (order by s.HeuristicScore desc nulls last, s.ViewCount desc nulls last, s.QuestionCreated asc nulls last) as GlobalRank
  from scored s
  left join user_enriched ue on ue.QuestionId = s.QuestionId
  cross join (
    select
      percentile_cont(0.9) within group (order by HeuristicScore) as p90_score
    from scored
  ) pct
),
anomalies as (
  select
    f.QuestionId,
    case
      when f.HeuristicScore > f.p90_score * 2 then 'OutlierHigh'
      when f.HeuristicScore < 0 and coalesce(f.ViewCount,0) > 10000 then 'HighViewsLowScore'
      when f.AcceptanceCategory = 'NoAccepted' and coalesce(f.AnswerCount,0) > 5 then 'ManyAnswersNoAccept'
      else null
    end as AnomalyLabel
  from (
    select
      fr.*,
      p.AnswerCount
    from final_rank fr
    left join Posts p on p.Id = fr.QuestionId
  ) f
)
select
  fr.GlobalRank,
  fr.QuestionId,
  fr.Title,
  fr.QuestionOwnerName,
  fr.Location,
  fr.Reputation,
  fr.GoldBadges,
  fr.SilverBadges,
  fr.BronzeBadges,
  fr.RankInLocation,
  fr.ViewCount,
  fr.QuestionScore,
  fr.NetVotesQ,
  fr.NetVotesAnsAgg,
  fr.FavoritesQ,
  fr.TagCount,
  fr.TagsOrderedByGlobalPopularity,
  fr.DuplicateLinks,
  fr.CloseEvents,
  fr.ReopenEvents,
  fr.AcceptanceCategory,
  fr.FirstAnswerScore,
  fr.TopAnswerScore,
  fr.AvgSecondsToAnswer,
  fr.SecondsToLastInteraction,
  round(cast(fr.HeuristicScore as numeric), 2) as HeuristicScore,
  coalesce(a.AnomalyLabel, 'OK') as AnomalyLabel,
  left(coalesce(fr.RecentCommentSnippets, ''), 200) as CommentSnippetSample
from final_rank fr
left join anomalies a on a.QuestionId = fr.QuestionId
where
  (
    (fr.NetVotesQ >= 5 and coalesce(fr.FavoritesQ,0) >= 3)
    or (fr.ViewCount >= 10000 and fr.TagCount >= 2)
    or (fr.AcceptanceCategory in ('Accepted=Top','Accepted=First') and coalesce(fr.TopAnswerScore,0) >= 5)
  )
  and not (fr.CloseEvents > 0 and fr.ReopenEvents = 0)
  and (
    fr.Location is distinct from 'Somewhere'
    or fr.Location is null
  )
order by fr.GlobalRank
limit 200;