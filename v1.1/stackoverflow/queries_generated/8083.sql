-- {"query": "8083.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 3407} 
with recent_questions as (
    select
        p.Id as QuestionId,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        coalesce(p.AnswerCount, 0) as AnswerCount
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts where PostTypeId = 1)
),
tag_expanded as (
    select
        rq.QuestionId,
        lower(trim(t)) as Tag
    from recent_questions rq
    cross join lateral unnest(string_to_array(substring(rq.Tags, 2, greatest(length(rq.Tags)-2,0)), '><')) as t
),
question_metrics as (
    select
        rq.QuestionId,
        rq.CreationDate,
        rq.OwnerUserId,
        rq.Score as QuestionScore,
        rq.ViewCount,
        rq.Title,
        rq.AnswerCount,
        -- Votes split
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotesOnQ,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotesOnQ,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as FavoritesOnQ,
        min(case when v.VoteTypeId in (8,9) then v.CreationDate end) as FirstBountyEvent,
        max(case when v.VoteTypeId in (8,9) then v.BountyAmount end) as MaxBountyAmount,
        count(distinct c.Id) as CommentCountOnQ
    from recent_questions rq
    left join Votes v on v.PostId = rq.QuestionId
    left join Comments c on c.PostId = rq.QuestionId
    group by rq.QuestionId, rq.CreationDate, rq.OwnerUserId, rq.Score, rq.ViewCount, rq.Title, rq.AnswerCount
),
answers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc, a.Id asc) as rn_by_score,
        rank() over (partition by a.ParentId order by a.CreationDate asc) as rank_by_first
    from Posts a
    where a.PostTypeId = 2
      and a.ParentId is not null
),
accepted_answers as (
    select
        q.Id as QuestionId,
        q.AcceptedAnswerId
    from Posts q
    where q.PostTypeId = 1
      and q.AcceptedAnswerId is not null
),
answer_aggregates as (
    select
        a.QuestionId,
        count(*) as AnswerTotal,
        sum(case when a.AnswerScore > 0 then 1 else 0 end) as PosAnswers,
        max(a.AnswerScore) as MaxAnswerScore,
        min(a.AnswerScore) as MinAnswerScore,
        avg(a.AnswerScore::numeric) as AvgAnswerScore,
        min(case when a.rank_by_first = 1 then a.AnswerCreationDate end) as FirstAnswerDate
    from answers a
    group by a.QuestionId
),
best_answers as (
    select
        a.QuestionId,
        a.AnswerId as TopScoringAnswerId,
        a.OwnerUserId as TopAnswererId,
        a.AnswerScore as TopAnswerScore
    from answers a
    where a.rn_by_score = 1
),
accepted_details as (
    select
        aa.QuestionId,
        aa.AcceptedAnswerId,
        a.OwnerUserId as AcceptedOwnerUserId,
        a.Score as AcceptedAnswerScore,
        a.CreationDate as AcceptedAnswerDate
    from accepted_answers aa
    left join Posts a on a.Id = aa.AcceptedAnswerId
),
user_stats as (
    select
        u.Id as UserId,
        u.Reputation,
        coalesce(u.UpVotes,0) as TotalUpVotes,
        coalesce(u.DownVotes,0) as TotalDownVotes,
        u.Views as ProfileViews,
        u.CreationDate as UserCreationDate,
        u.LastAccessDate as UserLastAccessDate,
        u.Location,
        -- Badge breakdown
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(b.Id) as TotalBadges,
        min(b.Date) as FirstBadgeDate,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.Reputation, u.UpVotes, u.DownVotes, u.Views, u.CreationDate, u.LastAccessDate, u.Location
),
question_user as (
    select
        qm.*,
        us.Reputation as OwnerReputation,
        us.TotalUpVotes as OwnerTotalUpVotes,
        us.TotalDownVotes as OwnerTotalDownVotes,
        us.TotalBadges as OwnerTotalBadges,
        us.GoldBadges as OwnerGold,
        us.SilverBadges as OwnerSilver,
        us.BronzeBadges as OwnerBronze,
        us.ProfileViews as OwnerProfileViews
    from question_metrics qm
    left join user_stats us on us.UserId = qm.OwnerUserId
),
edits as (
    select
        ph.PostId,
        count(*) filter (where ph.PostHistoryTypeId in (4,5,6,7,8,9,24)) as EditEvents,
        min(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6,7,8,9,24)) as FirstEditDate,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId in (4,5,6,7,8,9,24)) as LastEditDate,
        count(*) filter (where ph.PostHistoryTypeId = 10) as CloseVotes,
        bool_or(ph.PostHistoryTypeId = 11) as WasReopened,
        bool_or(ph.PostHistoryTypeId = 14) as WasLocked,
        count(*) filter (where ph.PostHistoryTypeId in (35,36)) as Migrations
    from PostHistory ph
    group by ph.PostId
),
duplicate_links as (
    select
        pl.PostId as QuestionId,
        count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks,
        count(*) filter (where pl.LinkTypeId = 1) as LinkedLinks,
        min(pl.CreationDate) as FirstLinkDate
    from PostLinks pl
    group by pl.PostId
),
tag_stats as (
    select
        te.Tag,
        count(distinct te.QuestionId) as QuestionsWithTag,
        avg(qm.ViewCount::numeric) as AvgViewsPerTag,
        percentile_cont(0.5) within group (order by qm.Score) as MedianScorePerTag
    from tag_expanded te
    join question_metrics qm on qm.QuestionId = te.QuestionId
    group by te.Tag
),
complex_predicate as (
    select
        qu.QuestionId,
        (
            (coalesce(qu.UpVotesOnQ,0) - coalesce(qu.DownVotesOnQ,0))::numeric
            + coalesce(qu.FavoritesOnQ,0)::numeric
            + coalesce(ba.TopAnswerScore, 0)::numeric
            + case when coalesce(ed.EditEvents,0) > 0 then 0.5 else 0 end
        ) / greatest(1, ln(2 + coalesce(qu.ViewCount,0))) as EngagementScore
    from question_user qu
    left join best_answers ba on ba.QuestionId = qu.QuestionId
    left join edits ed on ed.PostId = qu.QuestionId
),
first_activity as (
    select
        rq.QuestionId,
        least(
            rq.CreationDate,
            coalesce(aa.AcceptedAnswerDate, 'infinity'),
            coalesce(ag.FirstAnswerDate, 'infinity'),
            coalesce(ed.FirstEditDate, 'infinity'),
            coalesce(dl.FirstLinkDate, 'infinity')
        ) as FirstActivityDate
    from recent_questions rq
    left join accepted_details aa on aa.QuestionId = rq.QuestionId
    left join answer_aggregates ag on ag.QuestionId = rq.QuestionId
    left join edits ed on ed.PostId = rq.QuestionId
    left join duplicate_links dl on dl.QuestionId = rq.QuestionId
),
normalized as (
    select
        qu.QuestionId,
        qu.Title,
        regexp_replace(coalesce(qu.Title,''), '\s+', ' ', 'g') as NormalizedTitle,
        lower(trim(both ' ' from regexp_replace(coalesce(qu.Title,''), '\W+', ' ', 'g'))) as TitleLexeme,
        coalesce(string_agg(distinct te.Tag, '|' order by te.Tag), '') as TagList,
        length(coalesce(qu.Title,'')) as TitleLen,
        count(distinct te.Tag) as TagCount
    from question_user qu
    left join tag_expanded te on te.QuestionId = qu.QuestionId
    group by qu.QuestionId, qu.Title
),
leaderboard as (
    select
        qu.QuestionId,
        qu.CreationDate,
        qu.OwnerUserId,
        qu.QuestionScore,
        qu.ViewCount,
        qu.AnswerCount,
        qu.OwnerReputation,
        qu.OwnerTotalBadges,
        aa.AcceptedAnswerId,
        ad.AcceptedAnswerScore,
        ba.TopScoringAnswerId,
        ba.TopAnswerScore,
        ag.AnswerTotal,
        ag.AvgAnswerScore,
        ed.EditEvents,
        ed.CloseVotes,
        ed.WasReopened,
        dl.DuplicateLinks,
        cp.EngagementScore,
        fa.FirstActivityDate,
        n.NormalizedTitle,
        n.TagList,
        row_number() over (
            order by
                cp.EngagementScore desc nulls last,
                qu.ViewCount desc nulls last,
                qu.QuestionScore desc nulls last,
                qu.CreationDate desc
        ) as RankByEngagement,
        dense_rank() over (
            order by
                (coalesce(qu.OwnerReputation,0) / nullif(1 + coalesce(qu.OwnerTotalBadges,0),0)) asc nulls last
        ) as RankByOwnerRarity
    from question_user qu
    left join accepted_answers aa on aa.QuestionId = qu.QuestionId
    left join accepted_details ad on ad.QuestionId = qu.QuestionId
    left join best_answers ba on ba.QuestionId = qu.QuestionId
    left join answer_aggregates ag on ag.QuestionId = qu.QuestionId
    left join edits ed on ed.PostId = qu.QuestionId
    left join duplicate_links dl on dl.QuestionId = qu.QuestionId
    left join complex_predicate cp on cp.QuestionId = qu.QuestionId
    left join first_activity fa on fa.QuestionId = qu.QuestionId
    left join normalized n on n.QuestionId = qu.QuestionId
),
owner_activity as (
    select
        p.OwnerUserId as UserId,
        count(*) filter (where p.PostTypeId = 1) as QuestionsAuthored,
        count(*) filter (where p.PostTypeId = 2) as AnswersAuthored,
        sum(coalesce(p.Score,0)) as TotalPostScore,
        max(p.LastActivityDate) as LastPostActivity
    from Posts p
    group by p.OwnerUserId
),
final_union as (
    select
        l.QuestionId,
        'TOP'::text as Category,
        l.RankByEngagement as RankMetric,
        l.EngagementScore,
        l.ViewCount,
        l.QuestionScore,
        l.OwnerUserId,
        l.OwnerReputation,
        l.OwnerTotalBadges,
        l.AnswerCount,
        l.AnswerTotal,
        l.AvgAnswerScore,
        l.EditEvents,
        l.CloseVotes,
        l.DuplicateLinks,
        l.FirstActivityDate,
        l.NormalizedTitle,
        l.TagList
    from leaderboard l
    where l.RankByEngagement <= 100

    union all

    select
        l.QuestionId,
        'RECENT_HIGH_VIEW' as Category,
        dense_rank() over (order by l.ViewCount desc nulls last) as RankMetric,
        l.EngagementScore,
        l.ViewCount,
        l.QuestionScore,
        l.OwnerUserId,
        l.OwnerReputation,
        l.OwnerTotalBadges,
        l.AnswerCount,
        l.AnswerTotal,
        l.AvgAnswerScore,
        l.EditEvents,
        l.CloseVotes,
        l.DuplicateLinks,
        l.FirstActivityDate,
        l.NormalizedTitle,
        l.TagList
    from leaderboard l
    where l.CreationDate >= (select max(CreationDate) - interval '30 days' from Posts where PostTypeId = 1)
      and l.ViewCount >= (
        select percentile_cont(0.9) within group (order by ViewCount)
        from leaderboard
      )
),
owner_join as (
    select
        fu.*,
        oa.QuestionsAuthored,
        oa.AnswersAuthored,
        oa.TotalPostScore,
        ua.UserCreationDate,
        ua.UserLastAccessDate,
        coalesce(ua.Location,'') as OwnerLocation
    from final_union fu
    left join owner_activity oa on oa.UserId = fu.OwnerUserId
    left join user_stats ua on ua.UserId = fu.OwnerUserId
)
select
    oj.Category,
    oj.RankMetric,
    oj.QuestionId,
    oj.NormalizedTitle as Title,
    oj.TagList,
    oj.OwnerUserId,
    oj.OwnerReputation,
    oj.OwnerTotalBadges,
    oj.QuestionsAuthored,
    oj.AnswersAuthored,
    oj.TotalPostScore,
    oj.ViewCount,
    oj.QuestionScore,
    oj.AnswerCount,
    oj.AnswerTotal,
    round(coalesce(oj.AvgAnswerScore,0)::numeric, 3) as AvgAnswerScore,
    oj.EditEvents,
    oj.CloseVotes,
    oj.DuplicateLinks,
    to_char(oj.FirstActivityDate, 'YYYY-MM-DD"T"HH24:MI:SS') as FirstActivityISO,
    oj.OwnerLocation,
    -- Complex output expressions
    case
        when oj.OwnerReputation is null then 'anon'
        when oj.OwnerReputation >= 100000 then 'elite'
        when oj.OwnerReputation >= 10000 then 'expert'
        when oj.OwnerReputation >= 1000 then 'regular'
        else 'newbie'
    end as OwnerTier,
    case
        when oj.AnswerTotal is null or oj.AnswerTotal = 0 then null
        else round(100.0 * coalesce(oj.AnswerCount,0) / oj.AnswerTotal, 2)
    end as AnswerCompletionPct,
    left(md5(coalesce(oj.TagList,'')), 16) as TagFingerprint
from owner_join oj
where coalesce(oj.EngagementScore, 0) >= 0
  and (
        oj.OwnerReputation is null
        or (oj.OwnerReputation >= 0 and (oj.OwnerTotalBadges is null or oj.OwnerTotalBadges >= 0))
      )
  and not exists (
        select 1
        from PostLinks pl
        where pl.PostId = oj.QuestionId
          and pl.LinkTypeId = 3
          and pl.CreationDate > oj.FirstActivityDate
      )
order by
    oj.Category,
    oj.RankMetric,
    oj.QuestionId
limit 500;