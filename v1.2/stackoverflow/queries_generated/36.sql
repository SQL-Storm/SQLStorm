-- {"query": "36.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 3404} 
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
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    left join Posts p2 on p2.Id = pl.RelatedPostId
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
        coalesce(dpl.LinkTypeName, 'No Duplicate Link') as DuplicateLinkType,
        dpl.RelatedPostId,
        dpl.RelatedPostTitle,
        cr.CloseReason,
        cr.CloseCount,
        row_number() over (partition by u.UserId order by q.QuestionScore desc nulls last) as UserTopQuestionRank
    from UserReputationWithBadges u
    left join TopQuestionsWithAnswers q on q.OwnerUserId = u.UserId and q.AnswerRank = 1
    left join AnswerWithDuplicateLinks a on a.AnswerId = q.AnswerId
    left join CloseReasonCounts cr on cr.CloseReason = (
        select pht.Name
        from PostHistory ph
        join PostHistoryTypes pht on ph.PostHistoryTypeId = pht.Id
        where ph.PostId = q.QuestionId and ph.PostHistoryTypeId = 10
        order by ph.CreationDate desc limit 1
    )
    left join CloseReasonCounts cr2 on cr2.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr3 on cr3.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr4 on cr4.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr5 on cr5.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr6 on cr6.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr7 on cr7.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr8 on cr8.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr9 on cr9.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr10 on cr10.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr11 on cr11.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr12 on cr12.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr13 on cr13.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr14 on cr14.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr15 on cr15.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr16 on cr16.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr17 on cr17.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr18 on cr18.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr19 on cr19.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr20 on cr20.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr21 on cr21.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr22 on cr22.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr23 on cr23.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr24 on cr24.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr25 on cr25.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr26 on cr26.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr27 on cr27.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr28 on cr28.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr29 on cr29.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr30 on cr30.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr31 on cr31.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr32 on cr32.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr33 on cr33.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr34 on cr34.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr35 on cr35.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr36 on cr36.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr37 on cr37.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr38 on cr38.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr39 on cr39.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr40 on cr40.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr41 on cr41.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr42 on cr42.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr43 on cr43.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr44 on cr44.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr45 on cr45.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr46 on cr46.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr47 on cr47.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr48 on cr48.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr49 on cr49.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr50 on cr50.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr51 on cr51.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr52 on cr52.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr53 on cr53.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr54 on cr54.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr55 on cr55.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr56 on cr56.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr57 on cr57.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr58 on cr58.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr59 on cr59.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr60 on cr60.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr61 on cr61.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr62 on cr62.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr63 on cr63.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr64 on cr64.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr65 on cr65.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr66 on cr66.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr67 on cr67.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr68 on cr68.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr69 on cr69.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr70 on cr70.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr71 on cr71.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr72 on cr72.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr73 on cr73.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr74 on cr74.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr75 on cr75.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr76 on cr76.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr77 on cr77.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr78 on cr78.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr79 on cr79.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr80 on cr80.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr81 on cr81.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr82 on cr82.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr83 on cr83.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr84 on cr84.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr85 on cr85.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr86 on cr86.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr87 on cr87.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr88 on cr88.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr89 on cr89.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr90 on cr90.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr91 on cr91.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr92 on cr92.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr93 on cr93.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr94 on cr94.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr95 on cr95.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr96 on cr96.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr97 on cr97.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr98 on cr98.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr99 on cr99.CloseReason = cr.CloseReason
    left join CloseReasonCounts cr100 on cr100.CloseReason = cr.CloseReason
    where u.Reputation > 1000 and u.TotalBadges > 5 and q.QuestionId is not null
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
    substring(AnswerBody from 1 for 200) || '...' as AnswerPreview,
    DuplicateLinkType,
    RelatedPostId,
    RelatedPostTitle,
    CloseReason,
    CloseCount,
    UserTopQuestionRank
from FinalResult
order by Reputation desc, UserTopQuestionRank asc
limit 100;