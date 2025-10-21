-- {"query": "5097.sql", "dataset": "stackoverflow", "version": "v1.1", "prompt": "p1", "model": "gpt-4.1", "temperature": 1.0, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1099} 
with TopActiveUsers as (
    select
        u.Id as UserId,
        u.DisplayName,
        count(p.Id) as PostCount,
        sum(p.Score) as TotalScore,
        dense_rank() over(order by count(p.Id) desc, sum(p.Score) desc) as ActivityRank
    from Users u
    left join Posts p on p.OwnerUserId = u.Id
    where p.CreationDate > u.CreationDate
          and (p.Score > 5 or p.ViewCount > 1000)
    group by u.Id, u.DisplayName
    having count(p.Id) > 10
    limit 50
),
UserBadges as (
    select
        b.UserId,
        count(*) filter (where b.Class = 1) as GoldBadges,
        count(*) filter (where b.Class = 2) as SilverBadges,
        count(*) filter (where b.Class = 3) as BronzeBadges,
        max(b.Date) as LastBadgeDate
    from Badges b
    group by b.UserId
),
MostEditedQuestions as (
    select
        p.Id as QuestionId,
        p.Title,
        count(ph.Id) as EditCount,
        string_agg(distinct coalesce(u.DisplayName, ph.UserDisplayName), ', ') as Editors
    from Posts p
    join PostHistory ph on ph.PostId = p.Id and ph.PostHistoryTypeId in (4, 5, 6)
    left join Users u on u.Id = ph.UserId
    where p.PostTypeId = 1
    group by p.Id, p.Title
    having count(ph.Id) > 3
),
UserFavoriteTags as (
    select
        u.Id as UserId,
        t.TagName,
        count(*) as FavoriteTagCount,
        row_number() over(partition by u.Id order by count(*) desc) as FavTagRank
    from Users u
    join Posts p on p.OwnerUserId = u.Id
    join lateral (
        select unnest(string_to_array(substring(p.Tags, 2, length(p.Tags)-2), '><')) as TagName
    ) as t on true
    where p.PostTypeId = 1 and p.Tags is not null
    group by u.Id, t.TagName
)
select
    tau.UserId,
    tau.DisplayName,
    tau.PostCount,
    tau.TotalScore,
    ub.GoldBadges,
    ub.SilverBadges,
    ub.BronzeBadges,
    ub.LastBadgeDate,
    coalesce(uf.TagName, 'NoFavorite') as FavoriteTag,
    coalesce(uf.FavoriteTagCount, 0) as FavoriteTagCount,
    p.Id as LastPostId,
    p.Title as LastPostTitle,
    p.CreationDate as LastPostDate,
    mq.QuestionId as MostEditedQuestionId,
    mq.Title as MostEditedQuestionTitle,
    mq.EditCount as MostEditedEdits,
    mq.Editors as MostQuestionEditors,
    -- Calculate the upvotes/downvotes/favorites for the user’s last post using window functions
    upvotes.Count as LastPostUpvotes,
    downvotes.Count as LastPostDownvotes,
    favorites.Count as LastPostFavorites
from TopActiveUsers tau
left join UserBadges ub on ub.UserId = tau.UserId
left join lateral (
    select p.*
    from Posts p
    where p.OwnerUserId = tau.UserId
    order by p.CreationDate desc nulls last
    limit 1
) p on true
left join UserFavoriteTags uf
    on uf.UserId = tau.UserId and uf.FavTagRank = 1
left join lateral (
    select
        v.PostId,
        count(*) as Count
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId and vt.Name = 'UpMod'
    where v.PostId = p.Id
    group by v.PostId
) upvotes on upvotes.PostId = p.Id
left join lateral (
    select
        v.PostId,
        count(*) as Count
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId and vt.Name = 'DownMod'
    where v.PostId = p.Id
    group by v.PostId
) downvotes on downvotes.PostId = p.Id
left join lateral (
    select
        v.PostId,
        count(*) as Count
    from Votes v
    join VoteTypes vt on vt.Id = v.VoteTypeId and vt.Name = 'Favorite'
    where v.PostId = p.Id
    group by v.PostId
) favorites on favorites.PostId = p.Id
left join MostEditedQuestions mq
    on mq.QuestionId = (
        select pa.Id
        from Posts pa
        where pa.OwnerUserId = tau.UserId and pa.PostTypeId = 1
        order by (
            select count(*)
            from PostHistory ph
            where ph.PostId = pa.Id and ph.PostHistoryTypeId in (4, 5, 6)
        ) desc,
        pa.CreationDate asc
        limit 1
    )
order by tau.ActivityRank;