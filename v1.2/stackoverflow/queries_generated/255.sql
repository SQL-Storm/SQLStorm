-- {"query": "255.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1795} 
with RecursiveTagCounts as (
    select
        t.Id as TagId,
        t.TagName,
        t.Count,
        coalesce(p.AnswerCount, 0) as TotalAnswers,
        coalesce(p.ViewCount, 0) as TotalViews
    from Tags t
    left join Posts p on p.Id = t.ExcerptPostId and p.PostTypeId = 1
    where t.TagName is not null
),
UserBadgeStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(b.Id) filter (where b.Class = 1) as GoldBadges,
        count(b.Id) filter (where b.Class = 2) as SilverBadges,
        count(b.Id) filter (where b.Class = 3) as BronzeBadges,
        sum(case when b.TagBased = 1 then 1 else 0 end) as TagBasedBadges,
        row_number() over (partition by u.Id order by b.Date desc nulls last) as LastBadgeRank,
        max(b.Date) as LastBadgeDate
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
PostActivityWindow as (
    select
        p.Id,
        p.PostTypeId,
        p.OwnerUserId,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Tags,
        p.Title,
        p.AcceptedAnswerId,
        p.AnswerCount,
        p.CommentCount,
        p.FavoriteCount,
        p.ClosedDate,
        p.LastActivityDate,
        count(c.Id) over (partition by p.Id) as CommentCountWindow,
        rank() over (partition by p.OwnerUserId order by p.Score desc nulls last) as ScoreRankPerUser,
        dense_rank() over (order by p.ViewCount desc nulls last) as ViewRank
    from Posts p
    left join Comments c on c.PostId = p.Id
    where p.PostTypeId in (1, 2)
),
DuplicateQuestions as (
    select
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId,
        p1.Title as DuplicateTitle,
        p2.Title as OriginalTitle,
        pl.CreationDate as LinkCreationDate
    from PostLinks pl
    inner join Posts p1 on p1.Id = pl.PostId and p1.PostTypeId = 1
    inner join Posts p2 on p2.Id = pl.RelatedPostId and p2.PostTypeId = 1
    where pl.LinkTypeId = 3
),
UserRecentActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        max(p.LastActivityDate) as LastPostActivity,
        max(ph.CreationDate) as LastPostHistoryActivity,
        max(v.CreationDate) as LastVoteDate,
        max(c.CreationDate) as LastCommentDate
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join PostHistory ph on ph.UserId = u.Id
    left join Votes v on v.UserId = u.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName
),
ComplexUserStats as (
    select
        u.Id,
        u.DisplayName,
        u.Reputation,
        coalesce(b.GoldBadges, 0) as GoldBadges,
        coalesce(b.SilverBadges, 0) as SilverBadges,
        coalesce(b.BronzeBadges, 0) as BronzeBadges,
        coalesce(b.TagBasedBadges, 0) as TagBasedBadges,
        coalesce(a.LastPostActivity, '1970-01-01'::timestamp) as LastPostActivity,
        coalesce(a.LastPostHistoryActivity, '1970-01-01'::timestamp) as LastPostHistoryActivity,
        coalesce(a.LastVoteDate, '1970-01-01'::timestamp) as LastVoteDate,
        coalesce(a.LastCommentDate, '1970-01-01'::timestamp) as LastCommentDate,
        (select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 1 and p.ClosedDate is null) as OpenQuestionsCount,
        (select count(*) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2) as AnswersCount,
        (select avg(p.Score) from Posts p where p.OwnerUserId = u.Id and p.PostTypeId = 2) as AvgAnswerScore,
        (select count(distinct ph.PostId) from PostHistory ph where ph.UserId = u.Id and ph.PostHistoryTypeId in (4,5,6)) as EditCount
    from Users u
    left join UserBadgeStats b on b.UserId = u.Id
    left join UserRecentActivity a on a.UserId = u.Id
)
select
    c.Id as CommentId,
    c.Text as CommentText,
    c.CreationDate as CommentCreated,
    p.Id as PostId,
    p.Title as PostTitle,
    p.PostTypeId,
    p.Score as PostScore,
    p.ViewCount as PostViews,
    p.Tags,
    u.Id as OwnerUserId,
    u.DisplayName as OwnerName,
    u.Reputation as OwnerReputation,
    coalesce(cb.GoldBadges, 0) as OwnerGoldBadges,
    coalesce(cb.SilverBadges, 0) as OwnerSilverBadges,
    coalesce(cb.BronzeBadges, 0) as OwnerBronzeBadges,
    dt.OriginalQuestionId,
    dt.OriginalTitle,
    dt.LinkCreationDate,
    phc.Name as LastPostHistoryType,
    ph.CreationDate as LastPostHistoryDate,
    ph.Comment as LastPostHistoryComment,
    case
        when p.ClosedDate is not null then 'Closed'
        when p.AcceptedAnswerId is not null then 'Answered'
        else 'Open'
    end as PostStatus,
    row_number() over (partition by u.Id order by p.Score desc nulls last) as UserPostScoreRank,
    dense_rank() over (order by p.ViewCount desc nulls last) as GlobalViewRank,
    length(c.Text) as CommentLength,
    strpos(lower(c.Text), 'sql') > 0 as CommentMentionsSQL,
    coalesce(u.Location, 'Unknown') as UserLocation,
    coalesce(u.WebsiteUrl, 'No Website') as UserWebsite,
    coalesce(u.AboutMe, '') as UserAboutMe,
    coalesce(u.Views, 0) as UserViews,
    coalesce(u.UpVotes, 0) as UserUpVotes,
    coalesce(u.DownVotes, 0) as UserDownVotes,
    coalesce(u.ProfileImageUrl, '') as UserProfileImage,
    coalesce(u.EmailHash, '') as UserEmailHash,
    coalesce(u.AccountId, -1) as UserAccountId,
    case when u.LastAccessDate > now() - interval '30 days' then 1 else 0 end as ActiveLast30Days,
    case when u.CreationDate > now() - interval '1 year' then 1 else 0 end as NewUser,
    coalesce(cb.TagBasedBadges, 0) as OwnerTagBasedBadges
from Comments c
inner join Posts p on p.Id = c.PostId
left join Users u on u.Id = p.OwnerUserId
left join UserBadgeStats cb on cb.UserId = u.Id
left join PostHistory ph on ph.PostId = p.Id
    and ph.CreationDate = (
        select max(ph2.CreationDate) from PostHistory ph2 where ph2.PostId = p.Id
    )
left join PostHistoryTypes phc on ph.PostHistoryTypeId = phc.Id
left join DuplicateQuestions dt on dt.DuplicateQuestionId = p.Id
where
    (c.Text ilike '%performance%' or c.Text ilike '%benchmark%')
    and p.PostTypeId = 1
    and (p.Score > 5 or p.ViewCount > 1000)
    and (u.Reputation > 1000 or u.Id is null)
order by
    p.ViewCount desc nulls last,
    p.Score desc nulls last,
    c.CreationDate desc
limit 100;