with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        coalesce(p.Score, 0) as PostScore,
        row_number() over (partition by t.Id order by coalesce(p.Score, 0) desc, p.ViewCount desc) as rn
    from
        Tags t
        left join Posts p on p.Id = t.ExcerptPostId
    where
        t.IsModeratorOnly = false
),
RecentActiveUsers as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        u.Location,
        u.CreationDate,
        dense_rank() over (order by u.Reputation desc) as reputation_rank
    from Users u
    where u.Reputation > 1000 and u.LastAccessDate > (timestamp '2024-10-01 12:34:56') - interval '90' day
),
TopQuestions as (
    select 
        p.Id,
        p.Title,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.CreationDate,
        coalesce(a.AnswerCount, 0) as AnswerCount,
        p.FavoriteCount,
        p.ClosedDate,
        row_number() over (partition by p.OwnerUserId order by p.Score desc) as rnk
    from
        Posts p
        left join Posts a on a.ParentId = p.Id and a.PostTypeId = 2
    where
        p.PostTypeId = 1 and p.CreationDate > (timestamp '2024-10-01 12:34:56') - interval '1' year
),
UserBadgeAgg as (
    select 
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges
    from Badges b
    group by b.UserId
),
UserAnswerStats as (
    select
        p.OwnerUserId as UserId,
        count(*) filter (where p.Score >= 10) as HighScoreAnswers,
        avg(p.Score) as AvgAnswerScore,
        max(p.Score) as MaxAnswerScore,
        count(distinct ph.PostId) filter (where ph.PostHistoryTypeId = 10) as TimesPostClosed
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId = 10
    where p.PostTypeId = 2 
    group by p.OwnerUserId
),
UserVoteStats as (
    select
        v.UserId,
        count(*) filter (where vt.Name = 'UpMod') as UpVotesGiven,
        count(*) filter (where vt.Name = 'DownMod') as DownVotesGiven,
        count(*) filter (where vt.Name = 'Favorite') as FavoritesGiven
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId
    group by v.UserId
),
RecentCommentStats as (
    select
        c.UserId,
        count(*) as RecentComments,
        avg(c.Score) as AvgCommentScore,
        -- replace approx_percentile_disc with standard percentile_cont for median approximation
        percentile_cont(0.5) within group (order by length(c.Text)) as MedianCommentLength
    from Comments c
    where c.CreationDate > (timestamp '2024-10-01 12:34:56') - interval '30' day
    group by c.UserId
),
QuestionAnswerLink as (
    select
        q.Id as QuestionId,
        q.Title,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwner,
        lag(a.Score) over (partition by q.Id order by a.Score desc) as PrevAnswerScore
    from Posts q
    join Posts a on a.ParentId = q.Id and a.PostTypeId = 2
    where q.PostTypeId = 1
),
DuplicateLinkInfo as (
    select
        pl.PostId,
        pl.RelatedPostId,
        count(*) over (partition by pl.PostId) as DuplicateCount
    from PostLinks pl
    join LinkTypes lt on lt.Id = pl.LinkTypeId
    where lt.Name = 'Duplicate'
),
CloseReasonAggregates as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        count(*) as CloseCount
    from PostHistory ph
    join CloseReasonTypes crt on crt.Id = cast(ph.Comment as integer) and ph.PostHistoryTypeId = 10
    group by ph.PostId, crt.Name
),
FinalSelection as (
    select 
        u.Id as UserId,
        u.DisplayName,
        u.Location,
        u.Reputation,
        uba.GoldBadges,
        uba.SilverBadges,
        uba.BronzeBadges,
        uas.HighScoreAnswers,
        uas.AvgAnswerScore,
        uas.TimesPostClosed,
        uvs.UpVotesGiven,
        uvs.DownVotesGiven,
        uvs.FavoritesGiven,
        rcs.RecentComments,
        rcs.AvgCommentScore,
        dt.TagName,
        dt.Count as TagGlobalCount,
        dt.PostScore as TagExcerptPostScore,
        q.Title as TopQuestionTitle,
        q.Score as TopQuestionScore,
        q.AnswerCount,
        coalesce(dli.DuplicateCount, 0) as DuplicateLinksCount,
        coalesce(cra.CloseCount, 0) as TotalCloseVotes,
        cra.CloseReasonName
    from RecentActiveUsers u
    left join UserBadgeAgg uba on uba.UserId = u.Id
    left join UserAnswerStats uas on uas.UserId = u.Id
    left join UserVoteStats uvs on uvs.UserId = u.Id
    left join RecentCommentStats rcs on rcs.UserId = u.Id
    left join RecursiveTagCounts dt on (u.Location is not null and strpos(u.Location, dt.TagName) > 0) or strpos(coalesce(u.DisplayName,''), dt.TagName) > 0
    left join TopQuestions q on q.OwnerUserId = u.Id and q.rnk = 1
    left join DuplicateLinkInfo dli on dli.PostId = q.Id
    left join CloseReasonAggregates cra on cra.PostId = q.Id
    where u.Location is not null
)
select
    UserId,
    DisplayName,
    Location,
    Reputation,
    coalesce(GoldBadges,0) as GoldBadges,
    coalesce(SilverBadges,0) as SilverBadges,
    coalesce(BronzeBadges,0) as BronzeBadges,
    coalesce(HighScoreAnswers,0) as HighScoreAnswers,
    round(coalesce(AvgAnswerScore,0),2) as AvgAnswerScore,
    coalesce(TimesPostClosed,0) as TimesPostClosed,
    coalesce(UpVotesGiven,0) as UpVotesGiven,
    coalesce(DownVotesGiven,0) as DownVotesGiven,
    coalesce(FavoritesGiven,0) as FavoritesGiven,
    coalesce(RecentComments,0) as RecentComments,
    round(coalesce(AvgCommentScore,0),2) as AvgCommentScore,
    TagName,
    TagGlobalCount,
    TagExcerptPostScore,
    TopQuestionTitle,
    TopQuestionScore,
    AnswerCount,
    DuplicateLinksCount,
    TotalCloseVotes,
    CloseReasonName,
    case when Reputation > 50000 then 'Elite'
         when Reputation > 10000 then 'Expert'
         when Reputation > 1000 then 'Intermediate'
         else 'Novice'
    end as UserTier,
    case when coalesce(TimesPostClosed,0) > 5 then 'High Risk' else 'Low Risk' end as PostClosureRisk,
    concat_ws(' | ', DisplayName, Location, TagName) as UserSummary,
    coalesce(TopQuestionTitle, 'N/A') || ' [' || coalesce(cast(TopQuestionScore as varchar), '0') || ' pts]' as QuestionSummary
from FinalSelection
where (coalesce(GoldBadges,0) + coalesce(SilverBadges,0) + coalesce(BronzeBadges,0)) > 5
order by Reputation desc, coalesce(HighScoreAnswers,0) desc, coalesce(RecentComments,0) desc
limit 100;