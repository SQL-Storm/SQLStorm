-- {"query": "2307.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1640} 
with recursive TopTags as (
    select
        t.Id,
        t.TagName,
        t.Count,
        row_number() over (order by t.Count desc) as rn
    from Tags t
    where t.TagName is not null
),
Top100Tags as (
    select Id, TagName from TopTags where rn <= 100
),
PostsWithTopTags as (
    select
        p.Id,
        p.PostTypeId,
        p.CreationDate,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Tags,
        tt.TagName as TopTag
    from Posts p
    left join Top100Tags tt
        on strpos(p.Tags, concat('<', tt.TagName, '>')) > 0
    where p.PostTypeId in (1, 2)
),
UserBadgeCounts as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Badges b
    group by b.UserId
),
RecentActivity as (
    select
        p.OwnerUserId as UserId,
        max(p.LastActivityDate) as LastActivity,
        count(*) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(*) filter (where p.PostTypeId = 2) as AnswersGiven,
        sum(p.Score) as TotalScore
    from Posts p
    where p.OwnerUserId is not null
    group by p.OwnerUserId
),
TopUsers as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        ubc.GoldBadges,
        ubc.SilverBadges,
        ubc.BronzeBadges,
        ra.LastActivity,
        ra.QuestionsAsked,
        ra.AnswersGiven,
        ra.TotalScore,
        row_number() over (order by u.Reputation desc, ra.TotalScore desc) as UserRank
    from Users u
    left join UserBadgeCounts ubc on ubc.UserId = u.Id
    left join RecentActivity ra on ra.UserId = u.Id
    where u.Reputation > 1000
),
PostWithLinks as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.Score,
        p.ViewCount,
        p.OwnerUserId,
        p.CreationDate,
        pl.RelatedPostId,
        lt.Name as LinkTypeName
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
),
AnswerStats as (
    select
        p.ParentId as QuestionId,
        count(*) as AnswerCount,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore
    from Posts p
    where p.PostTypeId = 2
    group by p.ParentId
),
WindowedAnswers as (
    select
        p.Id,
        p.ParentId,
        p.Score,
        rank() over (partition by p.ParentId order by p.Score desc, p.CreationDate asc) as AnswerRank
    from Posts p
    where p.PostTypeId = 2
),
TopAnswerPerQuestion as (
    select
        wa.ParentId as QuestionId,
        wa.Id as AnswerId,
        wa.Score as AnswerScore
    from WindowedAnswers wa
    where wa.AnswerRank = 1
),
QuestionsWithTopAnswers as (
    select
        q.Id,
        q.Title,
        q.Score as QuestionScore,
        q.ViewCount,
        ta.AnswerId,
        ta.AnswerScore,
        ast.AnswerCount,
        ast.AvgAnswerScore
    from Posts q
    left join TopAnswerPerQuestion ta on ta.QuestionId = q.Id
    left join AnswerStats ast on ast.QuestionId = q.Id
    where q.PostTypeId = 1
),
CloseReasonCounts as (
    select
        cht.Comment as CloseReasonId, -- stored as string ids
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory cht
    left join CloseReasonTypes crt on crt.Id = cast(cht.Comment as int)
    where cht.PostHistoryTypeId = 10 -- Post Closed
    group by cht.Comment, crt.Name
    order by CloseCount desc
),
CorrelatedAnswersWithRecentVotes as (
    select
        a.Id,
        a.ParentId as QuestionId,
        a.Score,
        (
            select count(*) 
            from Votes v 
            where v.PostId = a.Id and v.VoteTypeId = 2 and v.CreationDate >= current_timestamp - interval '30 days'
        ) as RecentUpvotes,
        (
            select count(*) 
            from Votes v 
            where v.PostId = a.Id and v.VoteTypeId = 3 and v.CreationDate >= current_timestamp - interval '30 days'
        ) as RecentDownvotes
    from Posts a
    where a.PostTypeId = 2
)
select distinct
    tu.UserRank,
    tu.DisplayName,
    tu.Reputation,
    coalesce(tu.GoldBadges,0) as GoldBadges,
    coalesce(tu.SilverBadges,0) as SilverBadges,
    coalesce(tu.BronzeBadges,0) as BronzeBadges,
    to_char(tu.LastActivity, 'YYYY-MM-DD') as LastActivityDate,
    tu.QuestionsAsked,
    tu.AnswersGiven,
    tu.TotalScore,
    q.Title as TopQuestionTitle,
    q.QuestionScore,
    q.ViewCount as QuestionViews,
    q.AnswerId as TopAnswerId,
    q.AnswerScore as TopAnswerScore,
    q.AnswerCount,
    q.AvgAnswerScore,
    case
        when q.AnswerScore > tu.TotalScore / greatest(tu.AnswersGiven,1) then 'Top answer beats avg user answer score'
        else 'Top answer below avg user answer score'
    end as AnswerScoreComparison,
    cr.CloseReasonName,
    cr.CloseCount,
    string_agg(distinct pwt.TopTag, ', ' order by pwt.TopTag) as UserTopTags,
    sum(case when pav.RecentUpvotes is null then 0 else pav.RecentUpvotes end) as RecentAnswerUpvotes,
    sum(case when pav.RecentDownvotes is null then 0 else pav.RecentDownvotes end) as RecentAnswerDownvotes
from TopUsers tu
left join Posts q on q.OwnerUserId = tu.Id and q.PostTypeId = 1
left join QuestionsWithTopAnswers qwta on qwta.Id = q.Id
left join CloseReasonCounts cr on cr.CloseCount > 10
left join PostsWithTopTags pwt on pwt.OwnerUserId = tu.Id
left join CorrelatedAnswersWithRecentVotes pav on pav.QuestionId = q.Id
where tu.UserRank <= 50
group by
    tu.UserRank,
    tu.DisplayName,
    tu.Reputation,
    tu.GoldBadges,
    tu.SilverBadges,
    tu.BronzeBadges,
    tu.LastActivity,
    tu.QuestionsAsked,
    tu.AnswersGiven,
    tu.TotalScore,
    q.Title,
    q.Score,
    q.ViewCount,
    q.Id,
    q.AcceptedAnswerId,
    qwta.AnswerId,
    qwta.AnswerScore,
    qwta.AnswerCount,
    qwta.AvgAnswerScore,
    cr.CloseReasonName,
    cr.CloseCount
order by tu.UserRank;