with RecursiveFlagChanges as (
  select ph.PostId,
         ph.Direction,
         ph.CreationDate,
         ph.UserId,
         row_number() over (partition by ph.PostId order by ph.CreationDate) as ChangeSeq
    from (
      select phrow.PostId,
             case
               when phrow.PostHistoryTypeId = 10 then 1
               when phrow.PostHistoryTypeId = 11 then -1
               else 0
             end as Direction,
             phrow.CreationDate,
             phrow.UserId
        from PostHistory phrow
    ) ph
)
select PostId,
       Direction,
       CreationDate,
       UserId,
       ChangeSeq
  from RecursiveFlagChanges
;