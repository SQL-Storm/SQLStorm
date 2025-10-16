-- {"query": "491.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.4, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1846} 
with RecursiveTagHierarchy as (
    select
        t.Id,
        t.TagName,
        t.Count,
        t.ExcerptPostId,
        t.WikiPostId,
        1 as Level,
        cast(t.TagName as varchar(1000)) as Path
    from Tags t
    where t.Id in (
        select distinct unnest(string_to_array(substring(p.Tags from 2 for length(p.Tags) - 2), '><'))::int
        from Posts p
        where p.PostTypeId = 1 and p.Tags is not null
        limit 100
    )
    union all
    select
        t2.Id,
        t2.TagName,
        t2.Count,
        t2.ExcerptPostId,
        t2.WikiPostId,
        r.Level + 1,
        r.Path || ' > ' || t2.TagName
    from Tags t2
    join RecursiveTagHierarchy r on t2.Id = r.Id + 1
    where r.Level < 3
),
UserPostStats as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(p.Score), 0) as TotalPostScore,
        max(p.CreationDate) as LastPostDate,
        avg(p.Score) filter (where p.PostTypeId in (1,2)) as AvgPostScore,
        sum(case when p.AcceptedAnswerId is not null then 1 else 0 end) as QuestionsWithAcceptedAnswer,
        count(distinct b.Id) as BadgeCount,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName
),
TopPostsWithComments as (
    select
        p.Id,
        p.Title,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.OwnerUserId,
        u.DisplayName as OwnerName,
        count(c.Id) as CommentCount,
        max(c.CreationDate) as LastCommentDate,
        string_agg(distinct coalesce(c.UserDisplayName, 'Anonymous'), ', ') as CommenterNames,
        row_number() over (partition by p.OwnerUserId order by p.Score desc, p.ViewCount desc) as PostRankPerUser
    from Posts p
    left join Comments c on c.PostId = p.Id
    left join Users u on u.Id = p.OwnerUserId
    where p.PostTypeId in (1,2)
    group by p.Id, p.Title, p.Score, p.ViewCount, p.CreationDate, p.OwnerUserId, u.DisplayName
),
AcceptedAnswerStats as (
    select
        q.Id as QuestionId,
        q.Title as QuestionTitle,
        q.OwnerUserId as QuestionOwnerId,
        a.Id as AcceptedAnswerId,
        a.OwnerUserId as AnswerOwnerId,
        a.Score as AcceptedAnswerScore,
        a.CreationDate as AcceptedAnswerCreationDate,
        extract(epoch from (a.CreationDate - q.CreationDate))/3600 as HoursToAccept
    from Posts q
    join Posts a on a.Id = q.AcceptedAnswerId
    where q.PostTypeId = 1 and q.AcceptedAnswerId is not null
),
UserVoteAggregates as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(v.Id) filter (where v.VoteTypeId = 2) as UpVotesReceived,
        count(v.Id) filter (where v.VoteTypeId = 3) as DownVotesReceived,
        count(v.Id) filter (where v.VoteTypeId = 5) as FavoritesReceived,
        count(v.Id) filter (where v.VoteTypeId = 6) as CloseVotesCast,
        count(v.Id) filter (where v.VoteTypeId = 7) as ReopenVotesCast
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join Votes v on v.PostId = p.Id
    group by u.Id, u.DisplayName
),
PostCloseReasons as (
    select
        ph.PostId,
        crt.Name as CloseReasonName,
        ph.CreationDate as CloseDate,
        ph.UserId as ClosedByUserId,
        u.DisplayName as ClosedByUserName
    from PostHistory ph
    left join CloseReasonTypes crt on crt.Id = cast(ph.Comment as int)
    left join Users u on u.Id = ph.UserId
    where ph.PostHistoryTypeId = 10
),
ComplexUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct ph.Id) as TotalEdits,
        count(distinct ph.PostId) as EditedPosts,
        count(distinct case when ph.PostHistoryTypeId in (10,11) then ph.PostId end) as CloseReopenActions,
        count(distinct pl.Id) as LinkedPosts,
        max(ph.CreationDate) as LastActivity,
        bool_or(u.WebsiteUrl is not null and u.WebsiteUrl <> '') as HasWebsite,
        bool_or(u.AboutMe is not null and length(trim(u.AboutMe)) > 0) as HasAboutMe
    from Users u
    left join PostHistory ph on ph.UserId = u.Id
    left join PostLinks pl on pl.PostId in (
        select p.Id from Posts p where p.OwnerUserId = u.Id
    )
    group by u.Id, u.DisplayName, u.WebsiteUrl, u.AboutMe
)
select
    ups.UserId,
    ups.DisplayName,
    ups.QuestionCount,
    ups.AnswerCount,
    ups.TotalPostScore,
    ups.AvgPostScore,
    ups.GoldBadges,
    ups.SilverBadges,
    ups.BronzeBadges,
    uva.UpVotesReceived,
    uva.DownVotesReceived,
    uva.FavoritesReceived,
    uva.CloseVotesCast,
    uva.ReopenVotesCast,
    cua.TotalEdits,
    cua.EditedPosts,
    cua.CloseReopenActions,
    cua.LinkedPosts,
    cua.LastActivity,
    cua.HasWebsite,
    cua.HasAboutMe,
    coalesce(tp.PostRankPerUser, 0) as TopPostRank,
    tp.Title as TopPostTitle,
    tp.Score as TopPostScore,
    tp.ViewCount as TopPostViewCount,
    tp.CommentCount as TopPostCommentCount,
    tp.LastCommentDate as TopPostLastCommentDate,
    tp.CommenterNames as TopPostCommenters,
    (select avg(HoursToAccept) from AcceptedAnswerStats aas where aas.QuestionOwnerId = ups.UserId) as AvgHoursToAcceptAnswer,
    (select count(distinct ph.PostId) from PostHistory ph where ph.UserId = ups.UserId and ph.PostHistoryTypeId = 10) as CloseVotesCastViaHistory,
    (select count(distinct ph.PostId) from PostHistory ph where ph.UserId = ups.UserId and ph.PostHistoryTypeId = 11) as ReopenVotesCastViaHistory,
    (select count(distinct pl.RelatedPostId) from PostLinks pl where pl.PostId in (select p.Id from Posts p where p.OwnerUserId = ups.UserId)) as TotalLinkedPosts,
    string_agg(distinct rth.TagName, ', ') as SampleTagsUsed
from UserPostStats ups
left join UserVoteAggregates uva on uva.UserId = ups.UserId
left join ComplexUserActivity cua on cua.UserId = ups.UserId
left join TopPostsWithComments tp on tp.OwnerUserId = ups.UserId and tp.PostRankPerUser = 1
left join RecursiveTagHierarchy rth on rth.TagName = any(string_to_array(
    (select p.Tags from Posts p where p.OwnerUserId = ups.UserId and p.PostTypeId = 1 order by p.CreationDate desc limit 1), '><'))
where ups.QuestionCount > 5
  and ups.TotalPostScore > 50
  and (cua.HasWebsite = true or cua.HasAboutMe = true)
order by ups.TotalPostScore desc
limit 50;