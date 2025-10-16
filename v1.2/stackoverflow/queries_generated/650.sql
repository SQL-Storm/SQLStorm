-- {"query": "650.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1584} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        p.Id as PostId,
        p.PostTypeId,
        p.Score as PostScore,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.CreationDate as PostCreation,
        row_number() over (partition by u.Id order by p.CreationDate desc) as rn
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
),
UserTopPosts as (
    select * from RecursiveUserActivity where rn <= 5
),
PostVotesAgg as (
    select
        p.Id as PostId,
        sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
        sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes,
        sum(case when v.VoteTypeId = 1 then 1 else 0 end) as AcceptedVotes
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.Id
),
UserBadgesAgg as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        count(distinct case when b.TagBased = 1 then b.Name else null end) as TagBasedBadgeCount
    from Badges b
    group by b.UserId
),
QuestionCloseReasons as (
    select
        ph.PostId,
        cr.Name as CloseReason,
        count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes cr on cr.Id = cast(ph.Comment as int)
    where ph.PostHistoryTypeId = 10
    group by ph.PostId, cr.Name
),
UserAggregatedData as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        uba.GoldBadges,
        uba.SilverBadges,
        uba.BronzeBadges,
        uba.TagBasedBadgeCount,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(p.Score),0) as TotalPostScore,
        max(p.CreationDate) as LastPostDate,
        max(ph.CreationDate) filter (where ph.PostHistoryTypeId = 10) as LastCloseDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges uba on uba.UserId = u.Id
    left join PostHistory ph on ph.PostId = p.Id
    group by u.Id, u.DisplayName, u.Reputation, uba.GoldBadges, uba.SilverBadges, uba.BronzeBadges, uba.TagBasedBadgeCount
),
AnswerWithParentQuestion as (
    select
        a.Id as AnswerId,
        a.ParentId as QuestionId,
        q.Title as QuestionTitle,
        a.Score as AnswerScore,
        a.CreationDate as AnswerCreationDate,
        u.Id as AnswererUserId,
        u.DisplayName as AnswererName,
        row_number() over (partition by a.ParentId order by a.Score desc, a.CreationDate asc) as AnswerRank
    from Posts a
    join Posts q on q.Id = a.ParentId and q.PostTypeId = 1
    join Users u on u.Id = a.OwnerUserId
    where a.PostTypeId = 2
),
TopAnswers as (
    select * from AnswerWithParentQuestion where AnswerRank <= 3
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        u.DisplayName as LinkCreator,
        lt.Name as LinkTypeName
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    left join Users u on u.Id = (select OwnerUserId from Posts where Id = pl.PostId)
    where pl.LinkTypeId = 3
),
UserCommentStats as (
    select
        c.UserId,
        count(*) as CommentCount,
        avg(length(c.Text)) as AvgCommentLength,
        sum(c.Score) as TotalCommentScore,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.UserId
),
ComplexUserSummary as (
    select
        uad.UserId,
        uad.DisplayName,
        uad.Reputation,
        uad.GoldBadges,
        uad.SilverBadges,
        uad.BronzeBadges,
        uad.TagBasedBadgeCount,
        uad.QuestionCount,
        uad.AnswerCount,
        uad.TotalPostScore,
        uad.LastPostDate,
        uad.LastCloseDate,
        coalesce(ucs.CommentCount,0) as CommentCount,
        coalesce(ucs.AvgCommentLength,0) as AvgCommentLength,
        coalesce(ucs.TotalCommentScore,0) as TotalCommentScore,
        coalesce(ucs.LastCommentDate,uad.LastPostDate) as LastActivityDate
    from UserAggregatedData uad
    left join UserCommentStats ucs on ucs.UserId = uad.UserId
),
FinalResult as (
    select
        cus.UserId,
        cus.DisplayName,
        cus.Reputation,
        cus.GoldBadges,
        cus.SilverBadges,
        cus.BronzeBadges,
        cus.TagBasedBadgeCount,
        cus.QuestionCount,
        cus.AnswerCount,
        cus.TotalPostScore,
        cus.CommentCount,
        cus.AvgCommentLength,
        cus.TotalCommentScore,
        cus.LastActivityDate,
        ta.QuestionId,
        ta.QuestionTitle,
        ta.AnswerId,
        ta.AnswerScore,
        ta.AnswerCreationDate,
        ta.AnswerRank,
        dl.RelatedPostId as DuplicateOfPostId,
        dl.LinkCreator,
        dl.LinkTypeName,
        qcr.CloseReason,
        qcr.CloseCount
    from ComplexUserSummary cus
    left join TopAnswers ta on ta.AnswererUserId = cus.UserId
    left join DuplicateLinks dl on dl.PostId = ta.QuestionId
    left join QuestionCloseReasons qcr on qcr.PostId = ta.QuestionId
    where cus.Reputation > 2000
)
select
    UserId,
    DisplayName,
    Reputation,
    GoldBadges,
    SilverBadges,
    BronzeBadges,
    TagBasedBadgeCount,
    QuestionCount,
    AnswerCount,
    TotalPostScore,
    CommentCount,
    round(AvgCommentLength,2) as AvgCommentLength,
    TotalCommentScore,
    LastActivityDate,
    QuestionId,
    coalesce(QuestionTitle, 'N/A') as QuestionTitle,
    AnswerId,
    AnswerScore,
    AnswerCreationDate,
    AnswerRank,
    DuplicateOfPostId,
    coalesce(LinkCreator, 'System') as LinkCreator,
    LinkTypeName,
    CloseReason,
    CloseCount
from FinalResult
order by Reputation desc, TotalPostScore desc, LastActivityDate desc
limit 100;