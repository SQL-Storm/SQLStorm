with UserBadgeCounts as (
    select
        u.Id as UserId,
        u.DisplayName,
        u.Reputation,
        sum(case when b.Class = 1 then 1 else 0 end) as GoldBadges,
        sum(case when b.Class = 2 then 1 else 0 end) as SilverBadges,
        sum(case when b.Class = 3 then 1 else 0 end) as BronzeBadges
    from Users u
    left join Badges b on b.UserId = u.Id
    group by u.Id, u.DisplayName, u.Reputation
),
PostActivity as (
    SELECT
        p.Id as PostId,
        coalesce(p.Title, cast(p.Id as varchar)) as PostTitle,
        p.PostTypeId,
        p.OwnerUserId,
        p.Score,
        p.ViewCount,
        p.AnswerCount,
        p.FavoriteCount,
        case when p.AcceptedAnswerId is not null then 1 else 0 end as IsAcceptedQuestion,
        p.CreationDate,
        PI_NOT.SemVO as close_votes,
        PH_CLOSE.Comment as close_reason_code
    FROM Posts p
    left join LATERAL (
        SELECT count(*) as SemVO FROM Votes v
        WHERE v.PostId = p.Id
          and v.VoteTypeId = 6
    ) PI_NOT on true
    left join (
        select ph.PostId, ph.Comment
        from PostHistory ph
        where ph.PostHistoryTypeId = 10
    ) PH_CLOSE on PH_CLOSE.PostId = p.Id
)
select
    pa.PostId,
    pa.PostTitle,
    pa.PostTypeId,
    pa.OwnerUserId,
    pa.Score,
    pa.ViewCount,
    pa.AnswerCount,
    pa.FavoriteCount,
    pa.IsAcceptedQuestion,
    pa.CreationDate,
    pa.close_votes,
    pa.close_reason_code,
    ubc.UserId,
    ubc.DisplayName,
    ubc.Reputation,
    ubc.GoldBadges,
    ubc.SilverBadges,
    ubc.BronzeBadges
from PostActivity pa
left join Users u on u.Id = pa.OwnerUserId
left join UserBadgeCounts ubc on ubc.UserId = u.Id
where pa.PostTypeId in (1, 2)
order by pa.CreationDate desc;