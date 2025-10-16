-- {"query": "10.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1838} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        t.IsModeratorOnly,
        t.IsRequired,
        1 as Level,
        array[t.Id] as Path
    from Tags t
    where t.IsRequired = 1

    union all

    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        t2.IsModeratorOnly,
        t2.IsRequired,
        r.Level + 1,
        r.Path || t2.Id
    from Tags t2
    join RecursiveTagHierarchy r on t2.IsRequired = 1 and not t2.Id = any(r.Path)
    where r.Level < 3
),
UserBadgeCounts as (
    select
        b.UserId,
        b.Class,
        count(*) as BadgeCount
    from Badges b
    group by b.UserId, b.Class
),
UserReputationWindow as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        sum(p.Score) filter (where p.PostTypeId in (1,2)) as TotalPostScore,
        row_number() over (order by u.Reputation desc) as ReputationRank,
        rank() over (partition by u.Location order by u.Reputation desc) as LocationReputationRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location, u.Views, u.UpVotes, u.DownVotes
),
TopPostsWithComments as (
    select
        p.Id,
        p.PostTypeId,
        p.Title,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        coalesce(c.CommentCount, 0) as CommentCount,
        coalesce(vc.UpVotes, 0) as UpVotes,
        coalesce(vc.DownVotes, 0) as DownVotes,
        case when p.AcceptedAnswerId is not null then 1 else 0 end as HasAcceptedAnswer,
        row_number() over (partition by p.PostTypeId order by p.Score desc, p.ViewCount desc) as PostRank
    from Posts p
    left join Users u on u.Id = p.OwnerUserId
    left join (
        select PostId, count(*) as CommentCount
        from Comments
        group by PostId
    ) c on c.PostId = p.Id
    left join (
        select
            v.PostId,
            sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
            sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes
        from Votes v
        join VoteTypes vt on vt.Id = v.VoteTypeId
        group by v.PostId
    ) vc on vc.PostId = p.Id
    where p.PostTypeId in (1, 2)
),
DuplicateLinks as (
    select
        pl.PostId,
        pl.RelatedPostId,
        pl.CreationDate,
        u.DisplayName as LinkCreator
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId and lt.Name = 'Duplicate'
    left join Users u on u.Id = (select ph.UserId from PostHistory ph where ph.PostId = pl.PostId and ph.PostHistoryTypeId = 10 order by ph.CreationDate desc limit 1)
),
QuestionsWithCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReason,
        ph.CreationDate as CloseDate,
        ph.UserId as ClosedByUserId,
        u.DisplayName as ClosedByUserName
    from PostHistory ph
    join PostHistoryTypes pht on pht.Id = ph.PostHistoryTypeId and pht.Name = 'Post Closed'
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    left join Users u on u.Id = ph.UserId
    where ph.PostId in (select Id from Posts where PostTypeId = 1)
),
UserActivitySummary as (
    select
        u.Id,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionsPosted,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswersPosted,
        count(distinct c.Id) as CommentsMade,
        count(distinct v.Id) filter (where v.VoteTypeId = 2) as UpVotesGiven,
        count(distinct v.Id) filter (where v.VoteTypeId = 3) as DownVotesGiven,
        count(distinct b.Id) as BadgesEarned
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Comments c on c.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
TopUsersByActivity as (
    select
        uas.*,
        row_number() over (order by QuestionsPosted desc, AnswersPosted desc, CommentsMade desc) as ActivityRank
    from UserActivitySummary uas
),
FinalResult as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.Location,
        u.Views,
        u.UpVotes,
        u.DownVotes,
        ubc_badge.GoldBadges,
        ubc_badge.SilverBadges,
        ubc_badge.BronzeBadges,
        uas.QuestionsPosted,
        uas.AnswersPosted,
        uas.CommentsMade,
        tp.Id as TopPostId,
        tp.Title as TopPostTitle,
        tp.Score as TopPostScore,
        tp.ViewCount as TopPostViews,
        tp.CommentCount as TopPostComments,
        dup.PostId as DuplicatePostId,
        dup.RelatedPostId as DuplicateOfPostId,
        dup.LinkCreator as DuplicateLinkCreator,
        qcr.CloseReason,
        qcr.CloseDate,
        qcr.ClosedByUserName,
        urw.ReputationRank,
        urw.LocationReputationRank
    from Users u
    left join (
        select
            UserId,
            max(case when Class = 1 then BadgeCount else 0 end) as GoldBadges,
            max(case when Class = 2 then BadgeCount else 0 end) as SilverBadges,
            max(case when Class = 3 then BadgeCount else 0 end) as BronzeBadges
        from UserBadgeCounts
        group by UserId
    ) ubc_badge on ubc_badge.UserId = u.Id
    left join UserActivitySummary uas on uas.Id = u.Id
    left join TopPostsWithComments tp on tp.OwnerUserId = u.Id and tp.PostRank = 1
    left join DuplicateLinks dup on dup.PostId = tp.Id
    left join QuestionsWithCloseReasons qcr on qcr.PostId = tp.Id
    left join UserReputationWindow urw on urw.Id = u.Id
    where u.Reputation > 1000
)
select
    UserId,
    DisplayName,
    Reputation,
    Location,
    Views,
    UpVotes,
    DownVotes,
    coalesce(GoldBadges, 0) as GoldBadges,
    coalesce(SilverBadges, 0) as SilverBadges,
    coalesce(BronzeBadges, 0) as BronzeBadges,
    coalesce(QuestionsPosted, 0) as QuestionsPosted,
    coalesce(AnswersPosted, 0) as AnswersPosted,
    coalesce(CommentsMade, 0) as CommentsMade,
    TopPostId,
    TopPostTitle,
    TopPostScore,
    TopPostViews,
    TopPostComments,
    DuplicatePostId,
    DuplicateOfPostId,
    DuplicateLinkCreator,
    CloseReason,
    CloseDate,
    ClosedByUserName,
    ReputationRank,
    LocationReputationRank
from FinalResult
order by Reputation desc, QuestionsPosted desc
limit 50;