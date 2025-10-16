-- {"query": "12.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1676} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        1 as Level,
        array[t.TagName] as Path
    from Tags t
    where t.IsModeratorOnly = 0 and t.IsRequired = 0
    union all
    select
        t2.Id,
        t2.TagName,
        t2.Count,
        r.Level + 1,
        r.Path || t2.TagName
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id <> r.Id and not t2.TagName = any(r.Path)
    where t2.IsModeratorOnly = 0 and t2.IsRequired = 0 and r.Level < 3
),
UserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsAsked,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersGiven,
        count(distinct c.Id) as CommentsMade,
        coalesce(sum(vb.BountyAmount),0) as TotalBountyGiven,
        max(u.Reputation) as Reputation,
        row_number() over (order by max(u.Reputation) desc) as RankByReputation
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.CreationDate >= current_date - interval '365 days'
    left join Comments c on c.UserId = u.Id and c.CreationDate >= current_date - interval '365 days'
    left join Votes vb on vb.UserId = u.Id and vb.VoteTypeId = 8 and vb.CreationDate >= current_date - interval '365 days'
    group by u.Id, u.DisplayName
),
PostScoreStats as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        dense_rank() over (partition by p.PostTypeId order by p.Score desc) as ScoreRank,
        avg(p.Score) over (partition by p.PostTypeId) as AvgScore,
        count(*) over (partition by p.PostTypeId) as TotalPostsOfType
    from Posts p
    where p.CreationDate >= current_date - interval '180 days'
),
TopQuestionsWithAnswers as (
    select
        q.Id as QuestionId,
        q.Title,
        q.OwnerUserId,
        q.CreationDate as QuestionDate,
        q.Score as QuestionScore,
        q.ViewCount as QuestionViews,
        a.Id as AnswerId,
        a.OwnerUserId as AnswerOwnerUserId,
        a.CreationDate as AnswerDate,
        a.Score as AnswerScore,
        a.Body as AnswerBody,
        row_number() over (partition by q.Id order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts q
    left join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1 and q.Score > 10 and q.ViewCount > 1000
),
CloseReasonCounts as (
    select
        cht.Name as CloseReason,
        count(ph.Id) as CloseCount
    from PostHistory ph
    join PostHistoryTypes cht on ph.PostHistoryTypeId = cht.Id
    where ph.PostHistoryTypeId = 10 and ph.CreationDate >= current_date - interval '365 days'
    group by cht.Name
),
UserBadgeSummary as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
UserReputationWithBadges as (
    select
        ua.UserId,
        ua.DisplayName,
        ua.QuestionsAsked,
        ua.AnswersGiven,
        ua.CommentsMade,
        ua.TotalBountyGiven,
        ua.Reputation,
        coalesce(ubs.GoldBadges,0) as GoldBadges,
        coalesce(ubs.SilverBadges,0) as SilverBadges,
        coalesce(ubs.BronzeBadges,0) as BronzeBadges,
        coalesce(ubs.TotalBadges,0) as TotalBadges
    from UserActivity ua
    left join UserBadgeSummary ubs on ua.UserId = ubs.UserId
),
AnswerWithDuplicateLinks as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        a.OwnerUserId,
        a.Score,
        pl.LinkTypeId,
        lt.Name as LinkTypeName,
        pl.RelatedPostId,
        p2.Title as RelatedPostTitle
    from Posts a
    left join PostLinks pl on pl.PostId = a.Id and pl.LinkTypeId = 3
    left join LinkTypes lt on pl.LinkTypeId = lt.Id
    left join Posts p2 on pl.RelatedPostId = p2.Id
    where a.PostTypeId = 2
),
FinalResult as (
    select
        u.UserId,
        u.DisplayName,
        u.Reputation,
        u.QuestionsAsked,
        u.AnswersGiven,
        u.CommentsMade,
        u.TotalBountyGiven,
        u.GoldBadges,
        u.SilverBadges,
        u.BronzeBadges,
        u.TotalBadges,
        q.QuestionId,
        q.Title as QuestionTitle,
        q.QuestionScore,
        q.QuestionViews,
        a.AnswerId,
        a.AnswerScore,
        a.AnswerBody,
        coalesce(adl.LinkTypeName, 'No Duplicate Link') as DuplicateLinkType,
        coalesce(adl.RelatedPostTitle, 'N/A') as DuplicateRelatedPostTitle,
        cr.CloseReason,
        cr.CloseCount,
        rth.Level as TagHierarchyLevel,
        array_to_string(rth.Path, ' > ') as TagHierarchyPath
    from UserReputationWithBadges u
    left join TopQuestionsWithAnswers q on q.OwnerUserId = u.UserId and q.AnswerRank = 1
    left join Posts a on a.Id = q.AnswerId
    left join AnswerWithDuplicateLinks adl on adl.AnswerId = a.Id
    left join CloseReasonCounts cr on cr.CloseReason = (
        select pht.Name from PostHistory ph
        join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
        where ph.PostId = q.QuestionId and ph.PostHistoryTypeId = 10
        order by ph.CreationDate desc limit 1
    )
    left join RecursiveTagHierarchy rth on rth.TagName = any(string_to_array(coalesce(q.Tags, ''), '><'))
    where u.Reputation > 1000
    order by u.Reputation desc, q.QuestionScore desc nulls last
    limit 100
)
select
    UserId,
    DisplayName,
    Reputation,
    QuestionsAsked,
    AnswersGiven,
    CommentsMade,
    TotalBountyGiven,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    TotalBadges,
    QuestionId,
    QuestionTitle,
    QuestionScore,
    QuestionViews,
    AnswerId,
    AnswerScore,
    substring(AnswerBody from 1 for 100) || '...' as AnswerSnippet,
    DuplicateLinkType,
    DuplicateRelatedPostTitle,
    coalesce(CloseReason, 'Not Closed') as CloseReason,
    coalesce(CloseCount, 0) as CloseCount,
    TagHierarchyLevel,
    TagHierarchyPath
from FinalResult;