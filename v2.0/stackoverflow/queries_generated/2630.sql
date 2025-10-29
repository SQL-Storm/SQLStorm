-- {"query": "2630.sql", "dataset": "stackoverflow", "version": "v2.0", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1345} 
with RecursiveUserActivity as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        u.CreationDate,
        u.Location,
        count(distinct p.Id) filter (where p.PostTypeId = 1) as QuestionCount,
        count(distinct p.Id) filter (where p.PostTypeId = 2) as AnswerCount,
        coalesce(sum(p.Score), 0) as TotalPostScore,
        coalesce(sum(vtUp.CountUpVotes), 0) as TotalUpVotes,
        coalesce(sum(vtDown.CountDownVotes), 0) as TotalDownVotes,
        row_number() over (partition by u.Location order by u.Reputation desc) as RnkInLocation
    from
        Users u
        left join Posts p on p.OwnerUserId = u.Id
        left join (
            select
                PostId,
                count(*) as CountUpVotes
            from Votes v
            where VoteTypeId = 2
            group by PostId
        ) vtUp on vtUp.PostId = p.Id
        left join (
            select
                PostId,
                count(*) as CountDownVotes
            from Votes v
            where VoteTypeId = 3
            group by PostId
        ) vtDown on vtDown.PostId = p.Id
    group by
        u.Id, u.DisplayName, u.Reputation, u.CreationDate, u.Location
),
TopTagsByUser as (
    select
        ph.UserId,
        unnest(string_to_array(substring(p.Tags from 2 for char_length(p.Tags) - 2), '><')) as Tag,
        count(*) as TagUsage,
        row_number() over (partition by ph.UserId order by count(*) desc) as TagRank
    from
        PostHistory ph
        inner join Posts p on ph.PostId = p.Id
    where
        ph.PostHistoryTypeId in (3,6,9) -- Tags initial/edit/rollback
        and ph.UserId is not null
        and p.Tags is not null
    group by
        ph.UserId, Tag
),
UserBadgeSummary as (
    select
        UserId,
        count(*) filter (where Class = 1) as GoldBadges,
        count(*) filter (where Class = 2) as SilverBadges,
        count(*) filter (where Class = 3) as BronzeBadges,
        count(distinct Name) as UniqueBadges
    from
        Badges
    group by
        UserId
),
LatestPostPerUser as (
    select distinct on (OwnerUserId)
        p.OwnerUserId,
        p.Id as PostId,
        p.Title,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.CreationDate,
        p.Tags
    from Posts p
    where p.OwnerUserId is not null
    order by p.OwnerUserId, p.CreationDate desc
),
DuplicateQuestionsWithAnswers as (
    select
        pl.PostId as DuplicateQuestionId,
        pl.RelatedPostId as OriginalQuestionId,
        pq.Title as DuplicateTitle,
        pq.Tags as DuplicateTags,
        po.Title as OriginalTitle,
        po.Tags as OriginalTags,
        count(pa.Id) as AnswersToOriginal,
        count(da.Id) as AnswersToDuplicate
    from PostLinks pl
        inner join Posts pq on pq.Id = pl.PostId and pq.PostTypeId = 1
        inner join Posts po on po.Id = pl.RelatedPostId and po.PostTypeId = 1
        left join Posts pa on pa.ParentId = po.Id and pa.PostTypeId = 2
        left join Posts da on da.ParentId = pq.Id and da.PostTypeId = 2
    where
        pl.LinkTypeId = 3 -- Duplicate
    group by
        pl.PostId, pl.RelatedPostId, pq.Title, pq.Tags, po.Title, po.Tags
),
UserCommentStats as (
    select
        c.UserId,
        count(*) as CommentCount,
        avg(length(c.Text)) as AvgCommentLength,
        count(distinct c.PostId) as DistinctPostsCommented,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    where c.UserId is not null
    group by c.UserId
)
select
    u.UserId,
    u.DisplayName,
    u.Reputation,
    u.Location,
    u.QuestionCount,
    u.AnswerCount,
    u.TotalPostScore,
    u.TotalUpVotes,
    u.TotalDownVotes,
    coalesce(b.GoldBadges, 0) as GoldBadges,
    coalesce(b.SilverBadges, 0) as SilverBadges,
    coalesce(b.BronzeBadges, 0) as BronzeBadges,
    coalesce(b.UniqueBadges, 0) as UniqueBadges,
    c.CommentCount,
    c.AvgCommentLength,
    c.DistinctPostsCommented,
    c.LastCommentDate,
    lp.PostId as LatestPostId,
    lp.Title as LatestPostTitle,
    lp.PostTypeId as LatestPostType,
    lp.Score as LatestPostScore,
    lp.ViewCount as LatestPostViews,
    (select array_agg(Tag) from TopTagsByUser tt where tt.UserId = u.UserId and tt.TagRank <= 3) as TopTags
from
    RecursiveUserActivity u
    left join UserBadgeSummary b on b.UserId = u.UserId
    left join UserCommentStats c on c.UserId = u.UserId
    left join LatestPostPerUser lp on lp.OwnerUserId = u.UserId
where
    u.Reputation > (
        select avg(Reputation)*1.5 from Users
    )
    and u.Location is not null
    and exists (
        select 1
        from Posts p
        where p.OwnerUserId = u.UserId
        and p.PostTypeId in (1, 2)
        and p.Score >= (select percentile_cont(0.75) within group (order by Score) from Posts where OwnerUserId = u.UserId and PostTypeId in (1, 2))
    )
order by
    u.Reputation desc,
    u.Location,
    u.QuestionCount desc,
    u.AnswerCount desc
limit 100;