-- {"query": "1597.sql", "dataset": "stackoverflow", "version": "v1.2", "prompt": "p1", "model": "gpt-4.1-mini", "temperature": 1.5, "max_tokens": 16384, "reasoning": "minimal", "input_tokens": 2027, "output_tokens": 1195} 
with RecursiveUserPosts as (
    select
        u.Id as UserId,
        u.DisplayName,
        p.Id as PostId,
        p.Title,
        p.PostTypeId,
        p.Score,
        p.ViewCount,
        p.AcceptedAnswerId,
        p.CreationDate,
        p.Tags,
        dense_rank() over (partition by u.Id order by p.CreationDate desc) as PostRank
    from Users u
    join Posts p on u.Id = p.OwnerUserId
    where u.Reputation > 5000

    union all

    select
        rup.UserId,
        rup.DisplayName,
        pr.Id as PostId,
        pr.Title,
        pr.PostTypeId,
        pr.Score,
        pr.ViewCount,
        pr.AcceptedAnswerId,
        pr.CreationDate,
        pr.Tags,
        rup.PostRank + 1
    from RecursiveUserPosts rup
    join PostLinks pl on pl.PostId = rup.PostId and pl.LinkTypeId = 1
    join Posts pr on pr.Id = pl.RelatedPostId
    where rup.PostRank < 3
),
FilteredComments as (
    select
        c.PostId,
        count(*) filter(where c.UserId is not null) as KnownUserComments,
        count(*) filter(where c.UserId is null) as AnonymousComments,
        max(c.CreationDate) as LastCommentDate
    from Comments c
    group by c.PostId
),
RankedBadges as (
    select
        b.UserId,
        b.Name,
        b.Class,
        b.Date,
        row_number() over (partition by b.UserId order by b.Date desc) as Rnk
    from Badges b
    where b.Class <= 2
),
PostCloseReasons as (
    select
        ph.PostId,
        max(case when crt.Id is not null then crt.Name else 'Unknown' end) as CloseReason,
        max(ph.CreationDate) as CloseDate
    from PostHistory ph
    left join CloseReasonTypes crt on try_cast(ph.Comment as varchar) = cast(crt.Id as varchar)
    where ph.PostHistoryTypeId = 10
    group by ph.PostId
),
RankedVotes as (
    select
        v.PostId,
        v.VoteTypeId,
        count(*) over (partition by v.PostId, v.VoteTypeId) as VoteCount
    from Votes v
),
QuestionAgg as (
    select
        p.Id as QuestionId,
        p.OwnerUserId,
        p.Title,
        p.Tags,
        p.Score,
        p.ViewCount,
        p.AcceptedAnswerId,
        fce.CloseReason,
        fcm.KnownUserComments,
        fcm.AnonymousComments,
        fcm.LastCommentDate
    from Posts p
    left join PostCloseReasons fce on p.Id = fce.PostId
    left join FilteredComments fcm on p.Id = fcm.PostId
    where p.PostTypeId = 1
),
UserStats AS (
    select
        u.Id as UserId,
        u.DisplayName,
        count(distinct q.QuestionId) as OpenQuestions,
        count(distinct case when qcsaQ.Score > 10 then q.QuestionId end) as HotQuestionsCount,
        coalesce(sum(case when b.Class = 1 then 1 else 0 end), 0) as GoldBadges,
        coalesce(sum(case when b.Class = 2 then 1 else 0 end), 0) as SilverBadges,
        row_number() over (order by u.Reputation desc) topReputableUserRank
    from Users u
    left join QuestionAgg q on u.Id = q.OwnerUserId and q.CloseReason is null
    left join RankedBadges b on b.UserId = u.Id and b.Rnk <= 3
    left join LATERAL (
        select Ks.QuestionId, Ks.Score from QuestionAgg Ks
         where Ks.OwnerUserId = u.Id and Ks.Score > 10
         order by Ks.Score desc limit 1
    ) as qcsaQ on true
    group by u.Id, u.DisplayName
)
select 
    usp.UserId,
    usp.DisplayName,
    usp.HotQuestionsCount,
    usp.GoldBadges,
    usp.SilverBadges,
    rup.PostId,
    rup.Title,
    rup.PostTypeId,
    rup.Score,
    rup.ViewCount,
    InitialTags.Manager,
    coalesce(vcUps.UpVotes,0) as UserUpVotes,
    coalesce(vcDses.DownVotes,0) as UserDownVotes
from UserStats usp
join RecursiveUserPosts rup on rup.UserId = usp.UserId and rup.PostRank = 1
left join LATERAL (
    select unnest(string_to_array(substring(rup.Tags from 2 for length(rup.Tags)-2), '><')) as Manager
) InitialTags on true
left join lateral (
    select sum(case when v.VoteTypeId = 2 then 1 else 0 end) as UpVotes,
            sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes
    from Votes v
    where v.UserId = usp.UserId
) vcUPS on true
left join lateral (
    select sum(case when v.VoteTypeId = 3 then 1 else 0 end) as DownVotes
    from Votes v
    where v.UserId = usp.UserId
) vcDses on true
where usp.HotQuestionsCount > 1
order by usp.GoldBadges desc, usp.SilverBadges desc, rup.Score desc
limit 100;