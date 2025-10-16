-- {"query": "214.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 0.2, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1812} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.LastAccessDate,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        count(distinct c.Id) as CommentCount,
        coalesce(sum(v.VoteCount),0) as TotalVotesReceived,
        row_number() over (order by u.Reputation desc, u.LastAccessDate desc) as UserRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    left join (
        select PostId, count(*) as VoteCount
        from Votes
        where VoteTypeId in (2,3) -- UpMod and DownMod
        group by PostId
    ) v on v.PostId = p.Id
    left join Comments c on c.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.LastAccessDate
),
TopUsersCTE as (
    select UserId, DisplayName, Reputation, QuestionCount, AnswerCount, CommentCount, TotalVotesReceived, UserRank
    from RecursiveUserActivity
    where UserRank <= 100
),
PostDetails as (
    select
        p.Id,
        p.PostTypeId,
        pt.Name as PostTypeName,
        p.CreationDate,
        p.Score,
        p.ViewCount,
        p.Title,
        p.Tags,
        p.OwnerUserId,
        u.DisplayName as OwnerDisplayName,
        p.AcceptedAnswerId,
        p.ParentId,
        p.ClosedDate,
        p.LastActivityDate,
        row_number() over (partition by p.OwnerUserId order by p.Score desc nulls last) as UserPostRank
    from Posts p
    left join PostTypes pt on pt.Id = p.PostTypeId
    left join Users u on u.Id = p.OwnerUserId
    where p.OwnerUserId in (select UserId from TopUsersCTE)
),
AcceptedAnswerScores as (
    select
        q.Id as QuestionId,
        q.Title as QuestionTitle,
        q.OwnerUserId as QuestionOwnerId,
        a.Id as AnswerId,
        a.Score as AnswerScore,
        a.OwnerUserId as AnswerOwnerId
    from Posts q
    inner join Posts a on a.Id = q.AcceptedAnswerId and a.PostTypeId = 2
    where q.PostTypeId = 1
),
UserBadgeStats as (
    select
        b.UserId,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        count(*) as TotalBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    where b.UserId in (select UserId from TopUsersCTE)
    group by b.UserId
),
UserPostActivity as (
    select
        p.OwnerUserId,
        count(*) filter (where p.PostTypeId = 1 and p.ClosedDate is null) as OpenQuestions,
        count(*) filter (where p.PostTypeId = 1 and p.ClosedDate is not null) as ClosedQuestions,
        count(*) filter (where p.PostTypeId = 2) as Answers,
        count(distinct ph.PostId) filter (where ph.PostHistoryTypeId in (10,11)) as CloseReopenEvents
    from Posts p
    left join PostHistory ph on ph.PostId = p.Id
    where p.OwnerUserId in (select UserId from TopUsersCTE)
    group by p.OwnerUserId
),
UserLinkStats as (
    select
        p.OwnerUserId,
        count(distinct pl.Id) filter (where lt.Name = 'Duplicate') as DuplicateLinks,
        count(distinct pl.Id) filter (where lt.Name = 'Linked') as LinkedPosts
    from Posts p
    left join PostLinks pl on pl.PostId = p.Id
    left join LinkTypes lt on lt.Id = pl.LinkTypeId
    where p.OwnerUserId in (select UserId from TopUsersCTE)
    group by p.OwnerUserId
),
UserVotePatterns as (
    select
        v.UserId,
        count(*) filter (where vt.Name = 'UpMod') as UpVotesCast,
        count(*) filter (where vt.Name = 'DownMod') as DownVotesCast,
        count(*) filter (where vt.Name = 'Favorite') as FavoritesCast,
        count(*) filter (where vt.Name = 'Close') as CloseVotesCast
    from Votes v
    left join VoteTypes vt on vt.Id = v.VoteTypeId
    where v.UserId in (select UserId from TopUsersCTE)
    group by v.UserId
),
FinalUserStats as (
    select
        u.UserId,
        u.DisplayName,
        u.Reputation,
        u.QuestionCount,
        u.AnswerCount,
        u.CommentCount,
        u.TotalVotesReceived,
        coalesce(b.GoldBadges,0) as GoldBadges,
        coalesce(b.SilverBadges,0) as SilverBadges,
        coalesce(b.BronzeBadges,0) as BronzeBadges,
        coalesce(b.TotalBadges,0) as TotalBadges,
        coalesce(a.OpenQuestions,0) as OpenQuestions,
        coalesce(a.ClosedQuestions,0) as ClosedQuestions,
        coalesce(a.Answers,0) as Answers,
        coalesce(a.CloseReopenEvents,0) as CloseReopenEvents,
        coalesce(l.DuplicateLinks,0) as DuplicateLinks,
        coalesce(l.LinkedPosts,0) as LinkedPosts,
        coalesce(v.UpVotesCast,0) as UpVotesCast,
        coalesce(v.DownVotesCast,0) as DownVotesCast,
        coalesce(v.FavoritesCast,0) as FavoritesCast,
        coalesce(v.CloseVotesCast,0) as CloseVotesCast
    from TopUsersCTE u
    left join UserBadgeStats b on b.UserId = u.UserId
    left join UserPostActivity a on a.OwnerUserId = u.UserId
    left join UserLinkStats l on l.OwnerUserId = u.UserId
    left join UserVotePatterns v on v.UserId = u.UserId
)
select
    fus.UserId,
    fus.DisplayName,
    fus.Reputation,
    fus.QuestionCount,
    fus.AnswerCount,
    fus.CommentCount,
    fus.TotalVotesReceived,
    fus.GoldBadges,
    fus.SilverBadges,
    fus.BronzeBadges,
    fus.TotalBadges,
    fus.OpenQuestions,
    fus.ClosedQuestions,
    fus.Answers,
    fus.CloseReopenEvents,
    fus.DuplicateLinks,
    fus.LinkedPosts,
    fus.UpVotesCast,
    fus.DownVotesCast,
    fus.FavoritesCast,
    fus.CloseVotesCast,
    -- Complex string expression: concatenated badge summary
    concat_ws(' | ',
        'Gold: ' || fus.GoldBadges,
        'Silver: ' || fus.SilverBadges,
        'Bronze: ' || fus.BronzeBadges,
        'Total: ' || fus.TotalBadges
    ) as BadgeSummary,
    -- Window function: rank by reputation within badge class
    rank() over (partition by case
        when fus.GoldBadges > 10 then 'HighGold'
        when fus.GoldBadges between 1 and 10 then 'MidGold'
        else 'LowGold'
    end order by fus.Reputation desc) as RankWithinBadgeClass,
    -- Correlated subquery: average score of user's top 5 posts
    (
        select avg(p.Score)
        from Posts p
        where p.OwnerUserId = fus.UserId
        order by p.Score desc nulls last
        limit 5
    ) as AvgTop5PostScore,
    -- NULL logic: check if user has any posts with NULL Title (possible for answers)
    exists (
        select 1 from Posts p where p.OwnerUserId = fus.UserId and p.Title is null
    ) as HasPostsWithNullTitle
from FinalUserStats fus
order by fus.Reputation desc, fus.UserId
limit 50;