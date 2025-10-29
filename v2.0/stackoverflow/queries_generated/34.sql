-- {"query": "34.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2876} 
with
recent_questions as (
    select
        p.Id as QuestionId,
        p.CreationDate,
        p.OwnerUserId,
        p.Score as QuestionScore,
        p.ViewCount,
        p.Tags,
        p.Title,
        coalesce(p.AnswerCount, 0) as AnswerCount,
        (p.ClosedDate is not null)::int as IsClosed
    from Posts p
    where p.PostTypeId = 1
      and p.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts where PostTypeId = 1)
),
answers as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswerOwnerId,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate
    from Posts a
    where a.PostTypeId = 2
),
first_answer as (
    select
        a.QuestionId,
        min(a.AnswerCreationDate) as FirstAnswerAt
    from answers a
    group by a.QuestionId
),
votes_agg as (
    select
        v.PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as BountyStarted,
        sum(case when v.VoteTypeId = 9 then coalesce(v.BountyAmount,0) else 0 end) as BountyAwarded,
        count(*) filter (where v.VoteTypeId in (10,12)) as DeletionSpamVotes
    from Votes v
    group by v.PostId
),
comment_stats as (
    select
        c.PostId,
        count(*) as CommentCount,
        max(c.Score) as MaxCommentScore,
        avg(c.Score)::numeric(18,4) as AvgCommentScore,
        sum(case when c.Text ~* '\b(thanks|thank you|great|nice)\b' then 1 else 0 end) as PoliteCount
    from Comments c
    group by c.PostId
),
user_stats as (
    select
        u.Id as UserId,
        u.Reputation,
        u.UpVotes as UserUpVotes,
        u.DownVotes as UserDownVotes,
        extract(epoch from (now() - u.CreationDate)) / 86400.0 as AccountAgeDays,
        coalesce(nullif(b_geo.BadgeCount,0),0) as GoldBadges,
        coalesce(nullif(b_sil.BadgeCount,0),0) as SilverBadges,
        coalesce(nullif(b_bro.BadgeCount,0),0) as BronzeBadges
    from Users u
    left join (
        select UserId, count(*) as BadgeCount from Badges where Class = 1 group by UserId
    ) b_geo on b_geo.UserId = u.Id
    left join (
        select UserId, count(*) as BadgeCount from Badges where Class = 2 group by UserId
    ) b_sil on b_sil.UserId = u.Id
    left join (
        select UserId, count(*) as BadgeCount from Badges where Class = 3 group by UserId
    ) b_bro on b_bro.UserId = u.Id
),
tag_expand as (
    select
        q.QuestionId,
        unnest(string_to_array(substring(coalesce(q.Tags,''), 2, greatest(length(coalesce(q.Tags,'')) - 2, 0)), '><')) as TagName
    from recent_questions q
),
tag_top as (
    select
        t.TagName,
        sum(tg.Count) over (partition by t.TagName) as GlobalTagCount
    from tag_expand t
    left join Tags tg on lower(tg.TagName) = lower(t.TagName)
),
dup_links as (
    select
        pl.PostId as QuestionId,
        count(*) filter (where pl.LinkTypeId = 3) as DuplicateLinks,
        count(*) filter (where pl.LinkTypeId = 1) as LinkedLinks
    from PostLinks pl
    group by pl.PostId
),
close_reasons as (
    select
        ph.PostId as QuestionId,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as ClosedAt,
        max(case
            when ph.PostHistoryTypeId = 10 then
                nullif(trim(both '"' from split_part(ph.Comment, ',', 1)), '')
            else null
        end) as LastCloseReasonIdRaw
    from PostHistory ph
    where ph.PostHistoryTypeId in (10,11,12,13,14,15,19,20,35)
    group by ph.PostId
),
close_reason_name as (
    select
        cr.QuestionId,
        coalesce(crn.Name, 'Unknown') as CloseReasonName
    from close_reasons cr
    left join CloseReasonTypes crn on crn.Id::text = cr.LastCloseReasonIdRaw
),
activity_window as (
    select
        q.QuestionId,
        q.CreationDate,
        q.ViewCount,
        coalesce(v.UpVotes,0) as UpVotes,
        coalesce(v.DownVotes,0) as DownVotes,
        coalesce(c.CommentCount,0) as CommentCount,
        coalesce(c.MaxCommentScore,0) as MaxCommentScore,
        row_number() over (order by q.ViewCount desc, q.CreationDate desc) as rn_views_desc,
        ntile(10) over (order by q.ViewCount desc nulls last) as view_decile,
        rank() over (order by coalesce(v.UpVotes,0) - coalesce(v.DownVotes,0) desc) as net_vote_rank,
        sum(coalesce(v.UpVotes,0)) over (order by q.CreationDate rows between unbounded preceding and current row) as running_upvotes,
        avg(coalesce(c.CommentCount,0)) over (partition by date_trunc('month', q.CreationDate)) as avg_comments_in_month
    from recent_questions q
    left join votes_agg v on v.PostId = q.QuestionId
    left join comment_stats c on c.PostId = q.QuestionId
),
question_quality as (
    select
        q.QuestionId,
        q.Title,
        q.Tags,
        q.QuestionScore,
        q.ViewCount,
        q.AnswerCount,
        q.IsClosed,
        aw.view_decile,
        aw.net_vote_rank,
        coalesce(v.UpVotes,0) as UpVotes,
        coalesce(v.DownVotes,0) as DownVotes,
        coalesce(v.BountyStarted,0) as BountyStarted,
        coalesce(v.BountyAwarded,0) as BountyAwarded,
        coalesce(dl.DuplicateLinks,0) as DuplicateLinks,
        coalesce(dl.LinkedLinks,0) as LinkedLinks,
        coalesce(c.CommentCount,0) as CommentCount,
        coalesce(c.MaxCommentScore,0) as MaxCommentScore,
        coalesce(c.PoliteCount,0) as PoliteCommentCount,
        fa.FirstAnswerAt,
        extract(epoch from (fa.FirstAnswerAt - q.CreationDate))/60.0 as MinutesToFirstAnswer,
        case when q.AnswerCount > 0 then 1 else 0 end as HasAnswers,
        crn.CloseReasonName
    from recent_questions q
    left join votes_agg v on v.PostId = q.QuestionId
    left join comment_stats c on c.PostId = q.QuestionId
    left join dup_links dl on dl.QuestionId = q.QuestionId
    left join first_answer fa on fa.QuestionId = q.QuestionId
    left join close_reason_name crn on crn.QuestionId = q.QuestionId
    left join activity_window aw on aw.QuestionId = q.QuestionId
),
owner_enriched as (
    select
        qq.*,
        u.DisplayName as OwnerDisplayName,
        us.Reputation as OwnerReputation,
        us.AccountAgeDays,
        (coalesce(us.GoldBadges,0)*9 + coalesce(us.SilverBadges,0)*3 + coalesce(us.BronzeBadges,0)) as WeightedBadges
    from question_quality qq
    left join Posts p on p.Id = qq.QuestionId
    left join user_stats us on us.UserId = p.OwnerUserId
    left join Users u on u.Id = p.OwnerUserId
),
scored as (
    select
        oe.*,
        (
            coalesce(oe.UpVotes,0)*2
            - coalesce(oe.DownVotes,0)*1.5
            + least(coalesce(oe.ViewCount,0)/50.0, 1000)
            + case when oe.HasAnswers = 1 then 25 else -10 end
            + case when oe.DuplicateLinks > 0 then -20 else 0 end
            + case when oe.IsClosed = 1 then -50 else 0 end
            + least(greatest(300 - coalesce(oe.MinutesToFirstAnswer, 43200)/10.0, -100), 300)
            + coalesce(oe.OwnerReputation,0)/200.0
            + coalesce(oe.WeightedBadges,0)
            + coalesce(oe.PoliteCommentCount,0)*0.5
        ) as CompositeScore
    from owner_enriched oe
),
per_tag as (
    select
        te.TagName,
        s.QuestionId,
        s.CompositeScore,
        s.UpVotes,
        s.DownVotes,
        s.ViewCount,
        s.AnswerCount,
        s.MinutesToFirstAnswer,
        s.IsClosed
    from scored s
    join tag_expand te on te.QuestionId = s.QuestionId
),
tag_agg as (
    select
        pt.TagName,
        count(*) as Questions,
        avg(pt.CompositeScore) as AvgCompositeScore,
        percentile_cont(0.9) within group (order by pt.CompositeScore) as P90CompositeScore,
        sum(case when pt.IsClosed = 1 then 1 else 0 end) as ClosedCount,
        avg(pt.MinutesToFirstAnswer) as AvgMinsToFirstAnswer,
        sum(pt.UpVotes) as TotalUp,
        sum(pt.DownVotes) as TotalDown,
        sum(pt.ViewCount) as TotalViews
    from per_tag pt
    group by pt.TagName
),
tag_ranked as (
    select
        ta.*,
        dense_rank() over (order by ta.AvgCompositeScore desc nulls last) as RankByAvgScore,
        dense_rank() over (order by ta.P90CompositeScore desc nulls last) as RankByP90Score,
        dense_rank() over (order by ta.ClosedCount asc, ta.Questions desc) as RankByQuality
    from tag_agg ta
),
final_questions as (
    select
        s.QuestionId,
        s.Title,
        s.Tags,
        s.CompositeScore,
        s.UpVotes,
        s.DownVotes,
        s.ViewCount,
        s.AnswerCount,
        s.MinutesToFirstAnswer,
        s.CloseReasonName,
        s.IsClosed,
        row_number() over (order by s.CompositeScore desc nulls last, s.ViewCount desc) as rn
    from scored s
)
select
    fq.QuestionId,
    fq.Title,
    fq.Tags,
    fq.CompositeScore,
    fq.UpVotes,
    fq.DownVotes,
    fq.ViewCount,
    fq.AnswerCount,
    round(coalesce(fq.MinutesToFirstAnswer, -1)::numeric, 2) as MinutesToFirstAnswer,
    coalesce(fq.CloseReasonName, 'N/A') as CloseReasonName,
    fq.IsClosed,
    tr.TagName as RepresentativeTag,
    tr.AvgCompositeScore as TagAvgScore,
    tr.P90CompositeScore as TagP90Score,
    tr.ClosedCount as TagClosedCount,
    tr.RankByAvgScore,
    tr.RankByP90Score,
    tr.RankByQuality
from final_questions fq
left join lateral (
    select tr.*
    from tag_ranked tr
    join tag_expand te on te.TagName = tr.TagName and te.QuestionId = fq.QuestionId
    order by tr.RankByAvgScore, tr.RankByQuality
    limit 1
) tr on true
where fq.rn <= 200
union all
select
    null::int as QuestionId,
    '[TAG SUMMARY]' as Title,
    null::varchar(4000) as Tags,
    null::numeric as CompositeScore,
    null::int as UpVotes,
    null::int as DownVotes,
    null::int as ViewCount,
    null::int as AnswerCount,
    null::numeric as MinutesToFirstAnswer,
    null::varchar(200) as CloseReasonName,
    null::int as IsClosed,
    tr.TagName,
    tr.AvgCompositeScore,
    tr.P90CompositeScore,
    tr.ClosedCount,
    tr.RankByAvgScore,
    tr.RankByP90Score,
    tr.RankByQuality
from tag_ranked tr
where tr.Questions >= 10
order by 4 desc nulls last, 3 desc nulls last, 2 nulls last, 1 nulls last limit 500;