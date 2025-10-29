-- {"query": "495.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-5", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2026, "output_tokens": 2931} 
with recent_questions as (
    select
        p.Id as QuestionId,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        coalesce(nullif(trim(p.OwnerDisplayName), ''), u.DisplayName, '(unknown)') as OwnerName,
        row_number() over (partition by p.OwnerUserId order by p.CreationDate desc) as rn_owner_recent
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId = 1
      and p.CreationDate >= (select max(CreationDate) - interval '365 days' from Posts)
),
answers_aug as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId as AnswerUserId,
        a.CreationDate as AnswerCreationDate,
        a.Score as AnswerScore,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as rn_top_answer,
        dense_rank() over (partition by a.ParentId order by a.CreationDate asc) as dr_answer_order,
        sum(case when a.Score > 0 then 1 else 0 end) over (partition by a.ParentId) as pos_answer_cnt,
        count(*) over (partition by a.ParentId) as total_answer_cnt
    from Posts a
    where a.PostTypeId = 2
),
question_stats as (
    select
        rq.QuestionId,
        rq.OwnerUserId,
        rq.OwnerName,
        rq.Title,
        rq.Tags,
        rq.CreationDate,
        rq.Score as QuestionScore,
        rq.ViewCount,
        min(aa.AnswerCreationDate) as FirstAnswerDate,
        max(aa.AnswerScore) filter (where aa.rn_top_answer = 1) as TopAnswerScore,
        count(aa.AnswerId) as AnswerCount,
        max(aa.pos_answer_cnt) as PositiveAnswerCount,
        max(aa.total_answer_cnt) as TotalAnswerCount
    from recent_questions rq
    left join answers_aug aa on aa.QuestionId = rq.QuestionId
    group by rq.QuestionId, rq.OwnerUserId, rq.OwnerName, rq.Title, rq.Tags, rq.CreationDate, rq.Score, rq.ViewCount
),
owner_activity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        sum(case when p.PostTypeId = 1 then 1 else 0 end) as QuestionsAuthored,
        sum(case when p.PostTypeId = 2 then 1 else 0 end) as AnswersAuthored,
        sum(coalesce(p.Score,0)) as TotalPostScore,
        sum(coalesce(p.ViewCount,0)) as TotalViews,
        count(distinct date_trunc('day', p.CreationDate)) as ActiveDays,
        percentile_cont(0.5) within group (order by coalesce(p.Score,0)) as MedianPostScore
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
badge_summaries as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBadges,
        min(b.Date) as FirstBadgeDate,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
vote_summaries as (
    select
        v.PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 5 then 1 else 0 end) as Favorites,
        sum(case when v.VoteTypeId = 8 then coalesce(v.BountyAmount,0) else 0 end) as BountyStarted,
        sum(case when v.VoteTypeId = 9 then coalesce(v.BountyAmount,0) else 0 end) as BountyAwarded,
        min(v.CreationDate) filter (where v.VoteTypeId in (2,3)) as FirstVoteDate
    from Votes v
    group by v.PostId
),
closed_reasons as (
    select
        ph.PostId,
        max(case
            when ph.PostHistoryTypeId = 10 then
                case
                    when trim(ph.Comment) ~ '^[0-9]+$' then ph.Comment
                    else null
                end::int
            else null end) as CloseReasonId,
        max(case when ph.PostHistoryTypeId = 10 then ph.CreationDate end) as ClosedAt
    from PostHistory ph
    where ph.PostHistoryTypeId in (10,11,12,13,35)
    group by ph.PostId
),
duplicate_links as (
    select
        pl.PostId,
        count(*) filter (where pl.LinkTypeId = 3) as DuplicateOfCount,
        count(*) filter (where pl.LinkTypeId = 1) as LinkedCount,
        max(pl.CreationDate) as LastLinkDate
    from PostLinks pl
    group by pl.PostId
),
tag_split as (
    select
        qs.QuestionId,
        unnest(string_to_array(substring(qs.Tags, 2, greatest(length(qs.Tags)-2,0)), '><')) as tag
    from question_stats qs
    where qs.Tags is not null
),
question_tag_rank as (
    select
        ts.tag,
        count(*) as TagQuestionCount,
        avg(qs.QuestionScore) as AvgTagQuestionScore,
        rank() over (order by count(*) desc, avg(qs.QuestionScore) desc) as TagRankByFreq
    from tag_split ts
    join question_stats qs on qs.QuestionId = ts.QuestionId
    group by ts.tag
),
comment_agg as (
    select
        c.PostId,
        count(*) as CommentCount,
        max(c.Score) as MaxCommentScore,
        min(c.CreationDate) as FirstCommentDate,
        string_agg(left(coalesce(nullif(trim(c.Text), ''), '(empty)'), 50), ' | ' order by c.Score desc nulls last, c.CreationDate asc) as SampleComments
    from Comments c
    group by c.PostId
),
question_quality as (
    select
        qs.QuestionId,
        qs.OwnerUserId,
        qs.OwnerName,
        qs.Title,
        qs.Tags,
        qs.CreationDate,
        qs.QuestionScore,
        qs.ViewCount,
        coalesce(vs.UpVotes,0) as UpVotes,
        coalesce(vs.DownVotes,0) as DownVotes,
        coalesce(vs.Favorites,0) as Favorites,
        coalesce(vs.BountyStarted,0) as BountyStarted,
        coalesce(vs.BountyAwarded,0) as BountyAwarded,
        coalesce(cr.CloseReasonId,0) as CloseReasonId,
        cr.ClosedAt,
        coalesce(dl.DuplicateOfCount,0) as DuplicateOfCount,
        coalesce(dl.LinkedCount,0) as LinkedCount,
        qs.AnswerCount,
        qs.PositiveAnswerCount,
        qs.TotalAnswerCount,
        qa.TagDensity,
        ca.CommentCount,
        ca.MaxCommentScore,
        ca.FirstCommentDate,
        ca.SampleComments,
        -- composite quality score with varied expressions and null logic
        (
            (coalesce(vs.UpVotes,0) - coalesce(vs.DownVotes,0)) * 2
            + coalesce(qs.AnswerCount,0) * 1.5
            + case when cr.CloseReasonId is null then 5 else -10 end
            + case when coalesce(dl.DuplicateOfCount,0) > 0 then -5 else 0 end
            + ln(greatest(coalesce(qs.ViewCount,0) + 1, 1))
            + case when coalesce(vs.BountyAwarded,0) > 0 then 3 else 0 end
            + case when coalesce(ca.CommentCount,0) > 10 then -1 else 0 end
        ) as CompositeQuality
    from question_stats qs
    left join vote_summaries vs on vs.PostId = qs.QuestionId
    left join closed_reasons cr on cr.PostId = qs.QuestionId
    left join duplicate_links dl on dl.PostId = qs.QuestionId
    left join comment_agg ca on ca.PostId = qs.QuestionId
    left join lateral (
        select
            count(*)::float / nullif(cardinality(string_to_array(substring(qs.Tags, 2, greatest(length(qs.Tags)-2,0)), '><')),0) as TagDensity
        from generate_series(1, coalesce(qs.ViewCount,0)) gs
        where gs % greatest(cardinality(string_to_array(substring(qs.Tags, 2, greatest(length(qs.Tags)-2,0)), '><')),1) = 0
        limit 1
    ) qa on true
),
user_rollup as (
    select
        rq.OwnerUserId as UserId,
        count(*) as RecentQuestions,
        sum(qc.CompositeQuality) as SumCompositeQuality,
        avg(qc.CompositeQuality) as AvgCompositeQuality,
        max(qc.CompositeQuality) as MaxCompositeQuality,
        min(qc.CompositeQuality) as MinCompositeQuality,
        count(*) filter (where qc.CloseReasonId is not null and qc.CloseReasonId in (101,102,103,104,105)) as ClosedCount,
        sum(case when qc.DuplicateOfCount > 0 then 1 else 0 end) as DuplicateFlaggedCount
    from recent_questions rq
    join question_quality qc on qc.QuestionId = rq.QuestionId
    group by rq.OwnerUserId
),
top_users as (
    select
        oa.UserId,
        oa.DisplayName,
        oa.Reputation,
        oa.CreationDate,
        oa.LastAccessDate,
        oa.QuestionsAuthored,
        oa.AnswersAuthored,
        oa.TotalPostScore,
        oa.TotalViews,
        oa.ActiveDays,
        oa.MedianPostScore,
        coalesce(ur.RecentQuestions,0) as RecentQuestions,
        coalesce(ur.SumCompositeQuality,0) as SumCompositeQuality,
        coalesce(ur.AvgCompositeQuality,0) as AvgCompositeQuality,
        coalesce(ur.MaxCompositeQuality, null) as MaxCompositeQuality,
        coalesce(ur.MinCompositeQuality, null) as MinCompositeQuality,
        coalesce(ur.ClosedCount,0) as ClosedCount,
        coalesce(ur.DuplicateFlaggedCount,0) as DuplicateFlaggedCount,
        coalesce(bs.GoldBadges,0) as GoldBadges,
        coalesce(bs.SilverBadges,0) as SilverBadges,
        coalesce(bs.BronzeBadges,0) as BronzeBadges,
        coalesce(bs.TagBadges,0) as TagBadges,
        bs.FirstBadgeDate,
        bs.LastBadgeDate,
        row_number() over (order by coalesce(ur.SumCompositeQuality,0) desc, oa.Reputation desc, oa.TotalPostScore desc) as rn_by_quality
    from owner_activity oa
    left join user_rollup ur on ur.UserId = oa.UserId
    left join badge_summaries bs on bs.UserId = oa.UserId
),
final_questions as (
    select
        qq.*,
        qtr.Tag,
        qtr.TagRankByFreq,
        row_number() over (partition by qq.QuestionId order by qtr.TagRankByFreq nulls last, qtr.Tag asc) as rn_tag_rank
    from question_quality qq
    left join lateral (
        select ts.tag as Tag, qtr.TagRankByFreq
        from tag_split ts
        join question_tag_rank qtr on qtr.tag = ts.tag
        where ts.QuestionId = qq.QuestionId
        order by qtr.TagRankByFreq asc
        limit 3
    ) qtr on true
)
select
    tu.UserId,
    tu.DisplayName,
    tu.Reputation,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.TagBadges,
    tu.RecentQuestions,
    tu.SumCompositeQuality,
    tu.AvgCompositeQuality,
    tu.ClosedCount,
    tu.DuplicateFlaggedCount,
    fq.QuestionId,
    fq.Title,
    fq.OwnerName,
    fq.QuestionScore,
    fq.ViewCount,
    fq.UpVotes,
    fq.DownVotes,
    fq.Favorites,
    fq.AnswerCount,
    fq.PositiveAnswerCount,
    fq.TotalAnswerCount,
    fq.CompositeQuality,
    fq.Tag as TopAssociatedTag,
    fq.TagRankByFreq
from top_users tu
join final_questions fq on fq.OwnerUserId = tu.UserId and fq.rn_tag_rank = 1
where tu.rn_by_quality <= 50
qualify row_number() over (partition by tu.UserId order by fq.CompositeQuality desc nulls last, fq.ViewCount desc, fq.QuestionId desc) <= 5;