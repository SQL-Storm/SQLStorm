-- {"query": "1003.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1780} 
with RecursiveUserMetrics as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        count(distinct b.Id) as BadgeCount,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges,
        max(b.Date) as LastBadgeAwardDate,
        row_number() over (order by u.Reputation desc, u.Id) as Ranking
    from
        Users u
        left join Badges b on u.Id = b.UserId
    group by
        u.Id, u.DisplayName, u.Reputation
),
QuestionAnswerStats as (
    select
        p.OwnerUserId,
        count(distinct case when p.PostTypeId = 1 then p.Id end) as QuestionCount,
        count(distinct case when p.PostTypeId = 2 then p.Id end) as AnswerCount,
        avg(case when p.PostTypeId = 2 then coalesce(p.Score, 0) end) as AvgAnswerScore,
        max(case when p.PostTypeId = 2 then p.CreationDate end) as LastAnswerDate
    from
        Posts p
    where
        p.OwnerUserId is not null
    group by
        p.OwnerUserId
),
UserVoteStats as (
    select
        v.UserId,
        count(distinct v.Id) as TotalVotes,
        sum(case when vt.Name = 'UpMod' then 1 else 0 end) as UpVotes,
        sum(case when vt.Name = 'DownMod' then 1 else 0 end) as DownVotes,
        sum(case when vt.Name = 'Favorite' then 1 else 0 end) as Favorites
    from
        Votes v
        join VoteTypes vt on v.VoteTypeId = vt.Id
    where
        v.UserId is not null
    group by
        v.UserId
),
UserCommentAnalysis as (
    select
        c.UserId,
        count(distinct c.Id) as CommentCount,
        avg(length(c.Text)) as AvgCommentLength,
        max(c.CreationDate) as LastCommentDate
    from
        Comments c
    where
        c.UserId is not null
    group by
        c.UserId
),
TopTagsPerUser as (
    select
        p.OwnerUserId as UserId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as TagName,
        count(*) as TagUsageCount,
        row_number() over (partition by p.OwnerUserId order by count(*) desc) as TagRank
    from
        Posts p
    where
        p.Tags is not null and p.OwnerUserId is not null and p.PostTypeId = 1
    group by
        p.OwnerUserId,
        TagName
),
UserTopTag as (
    select
        t.UserId,
        t.TagName,
        t.TagUsageCount
    from
        TopTagsPerUser t
    where
        t.TagRank = 1
),
DuplicateLinkedPosts as (
    select
        pl.PostId,
        pl.RelatedPostId,
        p1.Title as OriginalTitle,
        p2.Title as DuplicateTitle,
        pl.CreationDate as LinkCreationDate
    from
        PostLinks pl
        join LinkTypes lt on pl.LinkTypeId = lt.Id
        join Posts p1 on pl.PostId = p1.Id
        join Posts p2 on pl.RelatedPostId = p2.Id
    where
        lt.Name = 'Duplicate'
),
UserActivityWindow as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.PostTypeId,
        p.CreationDate,
        count(*) over (partition by u.Id order by p.CreationDate rows between 29 preceding and current row) as PostsLast30Days
    from
        Users u
        left join Posts p on u.Id = p.OwnerUserId
),
UserSummary as (
    select
        rum.UserId,
        rum.DisplayName,
        rum.Reputation,
        rum.BadgeCount,
        rum.GoldBadges,
        rum.SilverBadges,
        rum.BronzeBadges,
        rum.LastBadgeAwardDate,
        coalesce(qas.QuestionCount, 0) as QuestionCount,
        coalesce(qas.AnswerCount, 0) as AnswerCount,
        coalesce(qas.AvgAnswerScore, 0) as AvgAnswerScore,
        coalesce(qas.LastAnswerDate, timestamp '2000-01-01') as LastAnswerDate,
        coalesce(uvs.TotalVotes, 0) as TotalVotes,
        coalesce(uvs.UpVotes, 0) as UpVotes,
        coalesce(uvs.DownVotes, 0) as DownVotes,
        coalesce(uvs.Favorites, 0) as Favorites,
        coalesce(uca.CommentCount, 0) as CommentCount,
        coalesce(uca.AvgCommentLength, 0) as AvgCommentLength,
        coalesce(uca.LastCommentDate, timestamp '2000-01-01') as LastCommentDate,
        ut.TagName as TopTagName,
        ut.TagUsageCount,
        max(uaw.PostsLast30Days) as PostsLast30Days
    from
        RecursiveUserMetrics rum
        left join QuestionAnswerStats qas on rum.UserId = qas.OwnerUserId
        left join UserVoteStats uvs on rum.UserId = uvs.UserId
        left join UserCommentAnalysis uca on rum.UserId = uca.UserId
        left join UserTopTag ut on rum.UserId = ut.UserId
        left join UserActivityWindow uaw on rum.UserId = uaw.UserId
    group by
        rum.UserId, rum.DisplayName, rum.Reputation, rum.BadgeCount, rum.GoldBadges, rum.SilverBadges, rum.BronzeBadges, rum.LastBadgeAwardDate,
        qas.QuestionCount, qas.AnswerCount, qas.AvgAnswerScore, qas.LastAnswerDate,
        uvs.TotalVotes, uvs.UpVotes, uvs.DownVotes, uvs.Favorites,
        uca.CommentCount, uca.AvgCommentLength, uca.LastCommentDate,
        ut.TagName, ut.TagUsageCount
)
select
    us.UserId,
    us.DisplayName,
    us.Reputation,
    us.BadgeCount,
    concat(
        'G:', us.GoldBadges, ' S:', us.SilverBadges, ' B:', us.BronzeBadges
    ) as BadgeBreakdown,
    to_char(us.LastBadgeAwardDate, 'YYYY-MM-DD') as LastBadgeDate,
    us.QuestionCount,
    us.AnswerCount,
    round(us.AvgAnswerScore, 2) as AvgAnswerScore,
    to_char(us.LastAnswerDate, 'YYYY-MM-DD') as LastAnswerDate,
    us.TotalVotes,
    us.UpVotes,
    us.DownVotes,
    us.Favorites,
    us.CommentCount,
    round(us.AvgCommentLength, 1) as AvgCommentLength,
    to_char(us.LastCommentDate, 'YYYY-MM-DD') as LastCommentDate,
    coalesce(us.TopTagName, 'N/A') as TopTag,
    us.TagUsageCount,
    us.PostsLast30Days,
    case
        when us.Reputation > 100000 then 'Legendary'
        when us.Reputation > 50000 then 'Experienced'
        when us.Reputation > 10000 then 'Intermediate'
        else 'Novice'
    end as ReputationLevel,
    exists (
        select 1
        from DuplicateLinkedPosts dlp
        where dlp.PostId in (
            select p.Id from Posts p where p.OwnerUserId = us.UserId and p.PostTypeId = 1
        )
        limit 1
    ) as HasDuplicateLinkedQuestions
from
    UserSummary us
where
    us.BadgeCount > 10 and us.QuestionCount > 5
order by
    us.Reputation desc,
    us.BadgeCount desc,
    us.QuestionCount desc
limit 50;