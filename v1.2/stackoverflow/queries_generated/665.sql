-- {"query": "665.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.6, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1527} 
with RecursiveUserActivity as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        p.Id as PostId,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate as PostCreationDate,
        row_number() over (partition by u.Id order by p.CreationDate) as PostNumber,
        count(*) over (partition by u.Id) as TotalPosts
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where u.Reputation > 1000
),
PostWithAcceptedAnswer as (
    select
        p.Id,
        p.Title,
        p.Tags,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.AcceptedAnswerId,
        a.Score as AcceptedAnswerScore,
        a.OwnerUserId as AcceptedAnswerUserId,
        a.CreationDate as AcceptedAnswerCreationDate
    from Posts p
    left join Posts a on p.AcceptedAnswerId = a.Id
    where p.PostTypeId = 1
),
UserBadgeStats as (
    select 
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
UserPostVotes as (
    select 
        p.OwnerUserId as UserId,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotesOnPosts,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotesOnPosts,
        count(v.Id) as TotalVotesOnPosts
    from Posts p
    left join Votes v on v.PostId = p.Id
    group by p.OwnerUserId
),
DuplicateLinks as (
    select 
        pl.PostId,
        pl.RelatedPostId,
        p.Title as PostTitle,
        rp.Title as RelatedPostTitle
    from PostLinks pl
    join Posts p on p.Id = pl.PostId
    join Posts rp on rp.Id = pl.RelatedPostId
    where pl.LinkTypeId = 3 -- Duplicate
),
QuestionsWithCloseReasons as (
    select 
        ph.PostId,
        ph.CreationDate as CloseDate,
        crt.Name as CloseReason,
        ph.UserId as ClosedByUserId,
        u.DisplayName as ClosedByUserName
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId = 10 -- Post Closed
),
RankedComments as (
    select 
        c.PostId,
        c.Id as CommentId,
        c.Text,
        c.Score,
        c.CreationDate,
        c.UserId,
        row_number() over (partition by c.PostId order by c.Score desc, c.CreationDate asc) as CommentRank
    from Comments c
),
TopComments as (
    select * from RankedComments where CommentRank <= 3
),
UserActivitySummary as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        coalesce(ubs.GoldBadges,0) as GoldBadges,
        coalesce(ubs.SilverBadges,0) as SilverBadges,
        coalesce(ubs.BronzeBadges,0) as BronzeBadges,
        coalesce(upv.UpVotesOnPosts,0) as UpVotesOnPosts,
        coalesce(upv.DownVotesOnPosts,0) as DownVotesOnPosts,
        coalesce(upv.TotalVotesOnPosts,0) as TotalVotesOnPosts,
        count(distinct p.Id) as TotalQuestions,
        count(distinct a.Id) as TotalAnswers,
        max(p.Score) as MaxQuestionScore,
        max(a.Score) as MaxAnswerScore,
        max(p.ViewCount) as MaxQuestionViews,
        max(a.CreationDate) as LastAnswerDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id and p.PostTypeId = 1
    left join Posts a on a.OwnerUserId = u.Id and a.PostTypeId = 2
    left join UserBadgeStats ubs on ubs.UserId = u.Id
    left join UserPostVotes upv on upv.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, ubs.GoldBadges, ubs.SilverBadges, ubs.BronzeBadges, upv.UpVotesOnPosts, upv.DownVotesOnPosts, upv.TotalVotesOnPosts
)
select 
    uas.UserId,
    uas.DisplayName,
    uas.Reputation,
    uas.GoldBadges,
    uas.SilverBadges,
    uas.BronzeBadges,
    uas.UpVotesOnPosts,
    uas.DownVotesOnPosts,
    uas.TotalVotesOnPosts,
    uas.TotalQuestions,
    uas.TotalAnswers,
    uas.MaxQuestionScore,
    uas.MaxAnswerScore,
    uas.MaxQuestionViews,
    uas.LastAnswerDate,
    pwa.Id as QuestionId,
    pwa.Title as QuestionTitle,
    pwa.Tags,
    pwa.Score as QuestionScore,
    pwa.ViewCount as QuestionViews,
    pwa.AcceptedAnswerId,
    pwa.AcceptedAnswerScore,
    pwa.AcceptedAnswerUserId,
    pwa.AcceptedAnswerCreationDate,
    cr.CloseReason,
    cr.CloseDate,
    cr.ClosedByUserName,
    string_agg(distinct dl.RelatedPostTitle, ', ') as DuplicateTitles,
    string_agg(distinct tc.Text, ' || ') as TopCommentsTexts
from UserActivitySummary uas
left join PostWithAcceptedAnswer pwa on pwa.Id in (
    select p.Id from Posts p where p.OwnerUserId = uas.UserId and p.PostTypeId = 1
)
left join QuestionsWithCloseReasons cr on cr.PostId = pwa.Id
left join DuplicateLinks dl on dl.PostId = pwa.Id
left join TopComments tc on tc.PostId = pwa.Id
where uas.Reputation > 2000
group by 
    uas.UserId, uas.DisplayName, uas.Reputation, uas.GoldBadges, uas.SilverBadges, uas.BronzeBadges, uas.UpVotesOnPosts, uas.DownVotesOnPosts, uas.TotalVotesOnPosts,
    uas.TotalQuestions, uas.TotalAnswers, uas.MaxQuestionScore, uas.MaxAnswerScore, uas.MaxQuestionViews, uas.LastAnswerDate,
    pwa.Id, pwa.Title, pwa.Tags, pwa.Score, pwa.ViewCount, pwa.AcceptedAnswerId, pwa.AcceptedAnswerScore, pwa.AcceptedAnswerUserId, pwa.AcceptedAnswerCreationDate,
    cr.CloseReason, cr.CloseDate, cr.ClosedByUserName
order by uas.Reputation desc, uas.TotalQuestions desc
limit 100;